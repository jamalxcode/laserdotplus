import AppKit
import LaserdotKit
import SwiftUI

enum ViewMode: String, CaseIterable { case list, grid }

/// Where the window looks: everything plugged in, this Mac, or one drive.
enum Place: Hashable {
    case everywhere, thisMac, drive(String)

    /// The search word for it (`volume:`), the drive's name folded as the
    /// engine folds names.
    var token: String? {
        switch self {
        case .everywhere: return nil
        case .thisMac: return "volume:local"
        case let .drive(name):
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            return "volume:\"" + folded.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
}

/// The window's state: what is searched, the filters ticked, the results,
/// the selection and its details. Privacy: nothing here is written to disk
/// except the view mode, sort and tile size (no names, no searches).
final class LibraryModel: ObservableObject {
    let engine: Engine

    @Published var text = "" { didSet { if text != oldValue { schedule() } } }
    @Published var place: Place = .everywhere { didSet { if place != oldValue { filters = [:]; schedule(now: true) } } }
    /// Ticked filter values, by group (several in a group: any of them).
    @Published private(set) var filters: [String: [String]] = [:]
    @Published var sort: SortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .modified {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort"); if sort != oldValue { schedule(now: true) } }
    }
    @Published var reverse = UserDefaults.standard.object(forKey: "reverse") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reverse, forKey: "reverse"); if reverse != oldValue { schedule(now: true) } }
    }
    @Published var viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    @Published var tileSize: Double = UserDefaults.standard.object(forKey: "tileSize") as? Double ?? 160 {
        didSet { UserDefaults.standard.set(tileSize, forKey: "tileSize") }
    }

    @Published private(set) var results: [Hit] = []
    @Published private(set) var total: UInt64 = 0
    @Published private(set) var groups: [RefineGroup] = []
    @Published private(set) var searching = false
    @Published private(set) var problem: String?
    @Published var selection: Set<String> = [] { didSet { if selection != oldValue { selectionChanged() } } }
    @Published private(set) var details: FileDetails?
    @Published private(set) var status: DaemonStatus?
    /// Something the window should say for a moment ("Moved 3 items to the Trash").
    @Published var notice: String?

    static let page = 500
    private var generation = 0
    private var pending: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "laserdotplus.search", qos: .userInitiated)
    private let refineQueue = DispatchQueue(label: "laserdotplus.refine", qos: .userInitiated)
    private let detailsQueue = DispatchQueue(label: "laserdotplus.details", qos: .userInitiated)
    private var statusTimer: Timer?

    init(engine: Engine) {
        self.engine = engine
    }

    // MARK: lifecycle

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let st = (try? self.engine.connect()) ?? self.engine.status()
            DispatchQueue.main.async {
                self.status = st
                self.indexThisMacOnce(st)
                self.schedule(now: true)
            }
        }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }

    /// This Mac's home folder is indexed on first use (its index stays on
    /// this Mac's own disk).
    private func indexThisMacOnce(_ st: DaemonStatus) {
        guard st.running, st.folders.isEmpty, !SelfTest.active else { return }
        index(folder: NSHomeDirectory())
    }

    func refreshStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let st = self.engine.status()
            DispatchQueue.main.async {
                let wasIndexing = self.status?.indexing != nil
                self.status = st
                // Results follow the index as it grows.
                if wasIndexing || st.indexing != nil { self.schedule(now: true, keepSelection: true) }
            }
        }
    }

    func drivesChanged() { schedule(now: true, keepSelection: true) }

    func index(folder: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = try? self?.engine.index(path: folder)
            DispatchQueue.main.async { self?.schedule(now: true, keepSelection: true) }
        }
    }

    func chooseFolderToIndex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("menu.indexFolder.prompt")
        if panel.runFront() == .OK, let url = panel.url { index(folder: url.path) }
    }

    // MARK: the search

    /// What is sent: the words typed, the place, then each group's ticked
    /// values (any of them: OR binds tighter than the space). With nothing
    /// typed or ticked: every file.
    var effectiveQuery: String {
        var parts: [String] = []
        let typed = text.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { parts.append(typed) }
        if let t = place.token { parts.append(t) }
        for g in groups.map(\.id) + filters.keys.filter({ id in !groups.contains { $0.id == id } }).sorted() {
            if let toks = filters[g], !toks.isEmpty { parts.append(toks.joined(separator: " OR ")) }
        }
        if typed.isEmpty { parts.append("-kind:folder") }
        return parts.joined(separator: " ")
    }

    func isOn(_ group: String, _ token: String) -> Bool { filters[group]?.contains(token) ?? false }

    func toggle(_ group: String, _ token: String) {
        var toks = filters[group] ?? []
        if let i = toks.firstIndex(of: token) { toks.remove(at: i) } else { toks.append(token) }
        filters[group] = toks.isEmpty ? nil : toks
        schedule(now: true)
    }

    func clearFilters() {
        filters = [:]
        schedule(now: true)
    }

    var hasFilters: Bool { !filters.isEmpty }

    /// Searches shortly after typing stops (at once for clicks).
    func schedule(now: Bool = false, keepSelection: Bool = false) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runSearch(keepSelection: keepSelection) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0 : 0.18), execute: work)
    }

    private func runSearch(keepSelection: Bool) {
        generation += 1
        let gen = generation
        let q = effectiveQuery
        let (sort, reverse, engine) = (self.sort, self.reverse, self.engine)
        searching = true
        searchQueue.async { [weak self] in
            let outcome = Result { try engine.search(query: q, limit: Self.page, sort: sort, reverse: reverse) }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.searching = false
                switch outcome {
                case let .success(r):
                    VideoFrames.noteDurations(r.hits)
                    self.results = r.hits
                    self.total = r.total
                    self.problem = r.notes.first
                    if keepSelection {
                        let paths = Set(r.hits.map(\.path))
                        self.selection = self.selection.filter { paths.contains($0) }
                    } else {
                        self.selection = []
                    }
                case let .failure(e):
                    self.results = []
                    self.total = 0
                    self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                }
                self.loadGroups(q, gen: gen)
            }
        }
    }

    /// The filter sidebar: what the results have, with counts.
    private func loadGroups(_ q: String, gen: Int) {
        let engine = self.engine
        refineQueue.async { [weak self] in
            let g = engine.refinements(query: q)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                // Drives are the sidebar's Places, not filters.
                self.groups = g.filter { $0.id != "drive" }
            }
        }
    }

    var canLoadMore: Bool { UInt64(results.count) < total }

    func loadMore() {
        let gen = generation
        let q = effectiveQuery
        let (sort, reverse, engine, offset) = (self.sort, self.reverse, self.engine, results.count)
        searchQueue.async { [weak self] in
            guard let r = try? engine.search(query: q, limit: Self.page, offset: offset, sort: sort, reverse: reverse) else { return }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                VideoFrames.noteDurations(r.hits)
                self.results += r.hits
            }
        }
    }

    // MARK: selection

    var selectedHits: [Hit] { results.filter { selection.contains($0.path) } }

    private func selectionChanged() {
        guard selection.count == 1, let path = selection.first else {
            details = nil
            return
        }
        let engine = self.engine
        detailsQueue.async { [weak self] in
            let d = try? engine.details(path: path)
            DispatchQueue.main.async {
                guard let self, self.selection == [path] else { return }
                self.details = d
            }
        }
    }

    /// The files an action applies to: the selection, or the one clicked
    /// when it is not part of it (as in Finder).
    func targets(_ clicked: String?) -> [Hit] {
        if let c = clicked, !selection.contains(c) { return results.filter { $0.path == c } }
        return selectedHits
    }

    // MARK: actions

    func open(_ hits: [Hit]) {
        hits.forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0.path)) }
    }

    func reveal(_ hits: [Hit]) {
        guard !hits.isEmpty else { return }
        Finder.reveal(hits.map { URL(fileURLWithPath: $0.path) })
    }

    func copyPaths(_ hits: [Hit]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hits.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func quickLook(_ hits: [Hit]? = nil) {
        let list = hits ?? selectedHits
        guard let first = list.first else { return }
        let urls = results.map { URL(fileURLWithPath: $0.path) }
        let i = results.firstIndex { $0.path == first.path } ?? 0
        QuickLook.shared.toggle(urls, at: i)
    }

    /// Move to the Trash, undoable (⌘Z) through the window's undo manager.
    func trash(_ hits: [Hit], undo: UndoManager?) {
        trashPaths(hits.map(\.path), undo: undo)
    }

    func trashPaths(_ paths: [String], undo: UndoManager?) {
        guard !paths.isEmpty else { return }
        var moved: [(from: URL, to: URL)] = []
        var failed = 0
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var out: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &out)
                if let to = out as URL? { moved.append((url, to)) }
            } catch {
                failed += 1
            }
        }
        let gone = Set(moved.map(\.from.path))
        results.removeAll { gone.contains($0.path) }
        selection.subtract(gone)
        total -= UInt64(min(UInt64(gone.count), total))
        notice = failed == 0 ? String(format: L("notice.trashed"), moved.count)
                             : String(format: L("notice.trashedSome"), moved.count, failed)
        undo?.registerUndo(withTarget: self) { model in model.restore(moved, undo: undo) }
        undo?.setActionName(L("action.trash"))
        tellEngine(moved.map(\.from))
    }

    private func restore(_ moved: [(from: URL, to: URL)], undo: UndoManager?) {
        var back: [(from: URL, to: URL)] = []
        for m in moved where (try? FileManager.default.moveItem(at: m.to, to: m.from)) != nil {
            back.append(m)
        }
        notice = String(format: L("notice.restored"), back.count)
        undo?.registerUndo(withTarget: self) { model in model.trashPaths(back.map(\.from.path), undo: undo) }
        tellEngine(back.map(\.from))
        schedule(now: true, keepSelection: true)
    }

    /// The folders changed: the engine lists them again at once.
    private func tellEngine(_ urls: [URL]) {
        let folders = Set(urls.map { $0.deletingLastPathComponent().path })
        let engine = self.engine
        DispatchQueue.global(qos: .utility).async { folders.forEach { engine.touched(folder: $0) } }
    }
}
