import AppKit
import LaserdotKit
import SwiftUI

enum ViewMode: String, CaseIterable { case list, grid, sheet, timeline }

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
    /// The Find Duplicates panel is open over the files.
    @Published var showDupes = false
    lazy var dupes = DupesModel(engine: engine)
    lazy var junk = JunkModel(engine: engine)
    lazy var bigOld = BigOldModel(engine: engine)
    lazy var space = SpaceModel(engine: engine)
    let views = SavedViews()
    /// Which clean-up the Clean Up screen shows.
    @Published var cleanupTab = CleanupTab.duplicates

    /// Open the Clean Up screen on one of its tabs.
    func openCleanup(_ tab: CleanupTab) {
        cleanupTab = tab
        showDupes = true
    }

    /// The place, in words (the duplicates panel's title).
    var placeTitle: String {
        switch place {
        case .everywhere: return L("place.everywhere")
        case .thisMac: return L("place.thisMac")
        case let .drive(name): return name
        }
    }

    /// Where duplicates are looked for: the current place.
    var dupesScope: String { place.token ?? "" }

    /// Remembered between launches only when it is Everything or This Mac: a
    /// drive's name is not kept on this Mac (privacy).
    @Published var place: Place = UserDefaults.standard.string(forKey: "place") == "thisMac" ? .thisMac : .everywhere {
        didSet {
            if place != oldValue { filters = [:]; schedule(now: true) }
            switch place {
            case .thisMac: UserDefaults.standard.set("thisMac", forKey: "place")
            default: UserDefaults.standard.set("everywhere", forKey: "place")
            }
        }
    }
    /// The inspector (the file's preview and details) is shown; remembered.
    /// Last opened, by path, as read (kept for the session; never written).
    var openedCache: [String: Int64] = [:]
    @Published var showInspector = (UserDefaults.standard.object(forKey: "showInspector") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }
    /// Chosen filter values, by group (several in a group: any of them).
    @Published private(set) var filters: [String: [String]] = [:]
    /// Values left out (⌥-click): each is a "-" word.
    @Published private(set) var excluded: [String] = []
    /// How each chosen value reads, for its pill.
    private var labels: [String: String] = [:]
    /// More choices: every value of every group (remembered).
    @Published var allChoices = UserDefaults.standard.bool(forKey: "allChoices") {
        didSet { UserDefaults.standard.set(allChoices, forKey: "allChoices") }
    }
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
    /// A short message in the bottom bar; it goes by itself after a while.
    @Published var notice: String? {
        didSet {
            guard let n = notice, n != L("notice.selectingAll") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if self?.notice == n { self?.notice = nil }
            }
        }
    }
    /// Something went wrong (files that could not be moved, a rename that
    /// failed): stays until dismissed, unlike `notice`, which fades (the
    /// critique: "3 could not be moved" vanished after 8 seconds).
    @Published var trouble: String?
    /// Bumped by Edit ▸ Find (⌘F): the search box takes the keyboard.
    @Published var focusSearch = 0
    /// The clean-up tray: files marked (in review mode, or from a menu) to
    /// go to the Trash or to a folder; nothing moves until it is applied.
    @Published private(set) var tray: [String: TrayItem] = [:]
    /// Review mode: the result shown full-window (nil: not reviewing).
    @Published var reviewIndex: Int? { didSet { if reviewIndex == nil { sweep = nil } } }
    /// The "What is this?" sweep: review mode over only the files whose
    /// names say nothing (nil: review goes through every result).
    @Published var sweep: [Hit]?
    /// What review mode walks through.
    var reviewItems: [Hit] { sweep ?? results }

    static let page = 500
    private var generation = 0
    private var pending: DispatchWorkItem?
    private let searchQueue = DispatchQueue(label: "laserdotplus.search", qos: .userInitiated)
    private let refineQueue = DispatchQueue(label: "laserdotplus.refine", qos: .userInitiated)
    private let detailsQueue = DispatchQueue(label: "laserdotplus.details", qos: .userInitiated)
    private var statusTimer: Timer?
    private var goneTimer: Timer?
    private var checkingGone = false

    /// Files deleted or moved away in Finder leave the list even when the
    /// drive's file events never arrive (exFAT drives, like the owner's T5
    /// EVO, can lose them): every few seconds the top of the list is checked
    /// off the main thread; what is gone is dropped at once, and the engine
    /// is asked to list those folders again.
    func dropGone() {
        guard !checkingGone, !results.isEmpty else { return }
        checkingGone = true
        let paths = results.prefix(1500).map(\.path)
        let engine = self.engine
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let gone = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
            if !gone.isEmpty {
                Set(gone.map { ($0 as NSString).deletingLastPathComponent }).forEach { engine.touched(folder: $0) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.checkingGone = false
                guard !gone.isEmpty else { return }
                let before = self.results.count
                self.results.removeAll { gone.contains($0.path) }
                self.total -= UInt64(min(Int(self.total), before - self.results.count))
                self.selection.subtract(gone)
                self.schedule(now: true, keepSelection: true)
            }
        }
    }

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
        goneTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.dropGone() }
    }

    /// This Mac's home folder is indexed on first use (its index stays on
    /// this Mac's own disk).
    private func indexThisMacOnce(_ st: DaemonStatus) {
        guard st.running, st.folders.isEmpty, !SelfTest.active else { return }
        index(folder: NSHomeDirectory())
    }

    /// One status request at a time: if the engine is slow to answer, the
    /// timer does not pile up waiting threads (they starved the app until
    /// the window froze).
    private var statusInFlight = false
    func refreshStatus() {
        guard !statusInFlight else { return }
        statusInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let st = self.engine.status()
            DispatchQueue.main.async {
                self.statusInFlight = false
                let wasIndexing = self.status?.indexing != nil
                if let p = st.indexing {
                    if self.indexStart?.root != p.root { self.indexStart = (p.root, Date(), p.done) }
                } else {
                    self.indexStart = nil
                }
                let changed = st.changes != (self.status?.changes ?? st.changes)
                self.status = st
                // Results follow the index: a file deleted or moved away in
                // Finder leaves the list within a few seconds, one added
                // appears (the selection is kept where it still exists).
                if changed || wasIndexing || st.indexing != nil { self.schedule(now: true, keepSelection: true) }
            }
        }
    }

    /// Where an indexing run started (root, time, files done), for its time left.
    private var indexStart: (root: String, at: Date, done: UInt64)?

    /// "Indexing Home · 40% · about 3 min left" (the owner: waiting was opaque).
    var indexingText: String? {
        guard let p = status?.indexing else { return nil }
        let name = (p.root as NSString).lastPathComponent
        guard p.total > 0, p.done <= p.total else { return String(format: L("status.indexing"), name) }
        let pct = Int(Double(p.done) * 100 / Double(p.total))
        var text = String(format: L("status.indexingPct"), name, pct)
        if let s = indexStart, s.root == p.root, p.done > s.done {
            let rate = Double(p.done - s.done) / max(1, Date().timeIntervalSince(s.at))
            let left = Double(p.total - p.done) / max(rate, 0.001)
            if left.isFinite, left > 5 { text += " · " + String(format: L("status.left"), durationText(left)) }
        }
        return text
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
        parts += excluded.map { "-" + $0 }
        if typed.isEmpty { parts.append("-kind:folder") }
        return parts.joined(separator: " ")
    }

    func isOn(_ group: String, _ token: String) -> Bool { filters[group]?.contains(token) ?? false }

    func toggle(_ group: String, _ token: String, label: String? = nil) {
        if let label { labels[token] = label }
        var toks = filters[group] ?? []
        if let i = toks.firstIndex(of: token) { toks.remove(at: i) } else { toks.append(token) }
        filters[group] = toks.isEmpty ? nil : toks
        schedule(now: true)
    }

    func exclude(_ group: String, _ token: String, label: String) {
        labels[token] = label
        if var toks = filters[group], let i = toks.firstIndex(of: token) {
            toks.remove(at: i)
            filters[group] = toks.isEmpty ? nil : toks
        }
        if !excluded.contains(token) { excluded.append(token) }
        schedule(now: true)
    }

    var filtersForSaving: [String: [String]] { filters }
    var excludedForSaving: [String] { excluded }
    var labelsForSaving: [String: String] { labels }

    /// A saved view: its words and choices, in the current place.
    func apply(_ v: SavedView) {
        labels.merge(v.labels) { $1 }
        filters = v.filters
        excluded = v.excluded
        text = v.text
        schedule(now: true)
    }

    func clearFilters() {
        filters = [:]
        excluded = []
        place = .everywhere
        schedule(now: true)
    }

    var hasFilters: Bool { !filters.isEmpty || !excluded.isEmpty || place != .everywhere }

    struct Pill {
        let group: String?; let token: String; let label: String; let excluded: Bool
        var isPlace = false
    }

    /// The chosen place (a drive or This Mac — the owner: "when i choose a
    /// disk, it should be included and shown in the search bar"), then the
    /// chosen and left-out values, as pills in the search box.
    var pills: [Pill] {
        var out: [Pill] = []
        switch place {
        case .everywhere: break
        case .thisMac: out.append(Pill(group: nil, token: place.token ?? "", label: L("place.thisMac"), excluded: false, isPlace: true))
        case let .drive(name): out.append(Pill(group: nil, token: place.token ?? name, label: name, excluded: false, isPlace: true))
        }
        let chosen = filters.keys.sorted().flatMap { g in (filters[g] ?? []).map { Pill(group: g, token: $0, label: labels[$0] ?? $0, excluded: false) } }
        return out + chosen + excluded.map { Pill(group: nil, token: $0, label: labels[$0] ?? $0, excluded: true) }
    }

    func removePill(_ p: Pill) {
        if p.isPlace {
            place = .everywhere
        } else if p.excluded {
            excluded.removeAll { $0 == p.token }
            schedule(now: true)
        } else if let g = p.group {
            toggle(g, p.token)
        }
    }

    /// The choices still open: chosen values are pills, not chips.
    var openGroups: [RefineGroup] {
        let on = Set(filters.values.flatMap { $0 } + excluded)
        return groups.compactMap { g in
            let opts = g.options.filter { !on.contains($0.token) && !$0.isSelected && !$0.isExcluded }
            return opts.isEmpty ? nil : RefineGroup(id: g.id, family: g.family, options: opts)
        }
    }

    // MARK: select all

    /// Every file in the current place and search — with a drive chosen,
    /// the whole drive (the owner: "a way to select the whole drive"): the
    /// rest is loaded first (up to 200,000 files).
    func selectAll() {
        guard canLoadMore else {
            selection = Set(results.map(\.path))
            return
        }
        let gen = generation
        let q = effectiveQuery
        let (sort, reverse, engine, start, total) = (self.sort, self.reverse, self.engine, results.count, self.total)
        notice = L("notice.selectingAll")
        searchQueue.async { [weak self] in
            var more: [Hit] = []
            var offset = start
            while UInt64(offset) < total, offset < 200_000,
                  let r = try? engine.search(query: q, limit: 5000, offset: offset, sort: sort, reverse: reverse), !r.hits.isEmpty {
                more += r.hits
                offset += r.hits.count
            }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.results += more
                self.selection = Set(self.results.map(\.path))
                self.notice = nil
            }
        }
    }

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
                if keepSelection, NSEvent.pressedMouseButtons & 1 != 0 {
                    // A click or a selection box is under way: new results
                    // would move the files under the mouse. Shortly after.
                    self.schedule(now: false, keepSelection: true)
                    return
                }
                self.searching = false
                switch outcome {
                case let .success(r):
                    VideoFrames.noteDurations(r.hits)
                    self.results = r.hits
                    self.fillOpened(r.hits.map(\.path), gen: gen)
                    self.total = r.total
                    self.problem = r.notes.first
                    if let i = self.reviewIndex, i < self.reviewItems.count {
                        // Reviewing (or What Is This?): the file on screen stays
                        // selected, so its details and suggested name still come.
                        self.selectOne(self.reviewItems[i].path)
                    } else if keepSelection {
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
                self.fillOpened(r.hits.map(\.path), gen: gen)
            }
        }
    }

    /// Last opened (as macOS records it on each file) for the rows just
    /// loaded: read off the main thread, by the page, for the Last Opened
    /// column and the details.
    func fillOpened(_ paths: [String], gen: Int) {
        // Known ones from the cache (a refresh every few seconds while a drive
        // indexes must not read every file again); only new ones are read.
        let wanted = paths.filter { openedCache[$0] == nil }
        apply(openedCache, gen: gen)
        guard !wanted.isEmpty else { return }
        let engine = self.engine
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let times = engine.fileTimes(wanted)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.openedCache.count > 50_000 { self.openedCache = [:] }
                for t in times { self.openedCache[t.path] = t.opened }
                guard gen == self.generation else { return }
                self.apply(self.openedCache, gen: gen)
            }
        }
    }

    private func apply(_ opened: [String: Int64], gen: Int) {
        guard !opened.isEmpty else { return }
        for i in results.indices {
            if let o = opened[results[i].path], o != results[i].opened { results[i].opened = o }
        }
    }

    /// The Last Opened column sorts the rows loaded (the engine does not
    /// keep these dates).
    func sortByOpened(reverse: Bool) {
        results.sort { reverse ? $0.opened < $1.opened : $0.opened > $1.opened }
    }

    // MARK: selection

    /// The results by month of their date (modified), newest first.
    var months: [MonthGroup] {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var order: [String] = []
        var groups: [String: [IndexedHit]] = [:]
        let cal = Calendar.current
        for (i, h) in results.enumerated() {
            let d = Date(timeIntervalSince1970: TimeInterval(h.modified))
            let c = cal.dateComponents([.year, .month], from: d)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(IndexedHit(index: i, hit: h))
        }
        return order.sorted(by: >).map { key in
            let items = groups[key] ?? []
            let d = Date(timeIntervalSince1970: TimeInterval(items.first?.hit.modified ?? 0))
            return MonthGroup(id: key, title: f.string(from: d), items: items, bytes: items.reduce(0) { $0 + $1.hit.size })
        }
    }

    var selectedHits: [Hit] { results.filter { selection.contains($0.path) } }

    /// Select one file and make sure its details are (being) read — even
    /// when it was already the selection but its details are another file's
    /// (What Is This? then showed no suggested name).
    func selectOne(_ path: String) {
        if selection == [path] {
            if details?.path != path { selectionChanged() }
        } else {
            selection = [path]
        }
    }

    private func selectionChanged() {
        guard selection.count == 1, let path = selection.first else {
            details = nil
            return
        }
        let engine = self.engine
        detailsQueue.async { [weak self] in
            // A connection that broke (the engine was busy, restarted…) is
            // remade on the next try: a hiccup must not leave the panel empty.
            var d = try? engine.details(path: path)
            for wait in [0.3, 1.0, 2.0] where d == nil {
                Thread.sleep(forTimeInterval: wait)
                guard DispatchQueue.main.sync(execute: { self?.selection == [path] }) else { return }
                d = try? engine.details(path: path)
            }
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

    /// The self-test sees what would open instead of opening it.
    static var openHook: (([Hit]) -> Void)?

    /// Open with a chosen app (File ▸ Open With), not added to Recent Items.
    func open(_ hits: [Hit], with app: URL) {
        if let hook = Self.openHook { return hook(hits) }
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        NSWorkspace.shared.open(hits.map { URL(fileURLWithPath: $0.path) }, withApplicationAt: app, configuration: config)
    }

    /// Get Info (⌘I): the inspector shows the file's preview and details.
    func getInfo(_ hits: [Hit]) {
        if let h = hits.first, !selection.contains(h.path) { selectOne(h.path) }
        showInspector = true
    }

    /// Rename… (File menu, right-click): asks the new name, then renames
    /// (undoable).
    func renamePrompt(_ h: Hit, undo: UndoManager?) {
        guard let name = SavedViews.askName(L("rename.title"), current: h.name)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name != h.name, !name.contains("/") else { return }
        rename(h, to: name, undo: undo)
    }

    func open(_ hits: [Hit]) {
        if let hook = Self.openHook { return hook(hits) }
        // Privacy (the owner: "disable recent items recording in apple menu"):
        // a file opened from here is not added to  ▸ Recent Items.
        let config = NSWorkspace.OpenConfiguration()
        config.addsToRecentItems = false
        for h in hits {
            let url = URL(fileURLWithPath: h.path)
            if let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
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
        if failed == 0 {
            notice = String(format: L("notice.trashed"), moved.count)
        } else {
            trouble = String(format: L("notice.trashedSome"), moved.count, failed)
        }
        undo?.registerUndo(withTarget: self) { model in model.restore(moved, undo: undo) }
        undo?.setActionName(L("action.trash"))
        tellEngine(moved.map(\.from))
    }

    /// Many files to the Trash (duplicates) off the main thread — a drive
    /// may be slow — with macOS's own Trash call, undoable like `trashPaths`.
    /// `done` gets the paths that went and how many could not.
    func trashInBackground(_ paths: [String], undo: UndoManager?, done: @escaping (Set<String>, Int) -> Void) {
        guard !paths.isEmpty else { return done([], 0) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var moved: [(from: URL, to: URL)] = []
            var failed = 0
            for path in paths {
                let url = URL(fileURLWithPath: path)
                var out: NSURL?
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: &out)) != nil, let to = out as URL? {
                    moved.append((url, to))
                } else {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let gone = Set(moved.map(\.from.path))
                self.results.removeAll { gone.contains($0.path) }
                self.selection.subtract(gone)
                self.total -= UInt64(min(UInt64(gone.count), self.total))
                if !moved.isEmpty {
                    undo?.registerUndo(withTarget: self) { model in model.restore(moved, undo: undo) }
                    undo?.setActionName(L("action.trash"))
                }
                self.tellEngine(moved.map(\.from))
                // The drives' Trash sizes change.
                Set(moved.compactMap { m -> String? in
                    let parts = m.from.path.split(separator: "/")
                    return parts.count > 2 && parts[0] == "Volumes" ? "/Volumes/" + parts[1] : nil
                }).forEach { DriveTrash.shared.refresh(mount: $0) }
                done(gone, failed)
            }
        }
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

    // MARK: the clean-up tray

    func mark(_ hits: [Hit], _ action: TrayAction) {
        for h in hits { tray[h.path] = TrayItem(hit: h, action: action) }
    }

    func unmark(_ paths: [String]) {
        paths.forEach { tray[$0] = nil }
    }

    func clearTray() { tray = [:] }

    var trayBytes: UInt64 { tray.values.reduce(0) { $0 + $1.hit.size } }
    func trayCount(_ action: TrayAction) -> Int { tray.values.filter { $0.action == action }.count }

    /// Apply the tray after one confirmation: the Trash for some, a folder
    /// (chosen now) for the others; one Undo puts everything back.
    func applyTray(undo: UndoManager?) {
        guard !tray.isEmpty else { return }
        let toTrash = tray.values.filter { $0.action == .trash }.map(\.hit.path)
        let toMove = tray.values.filter { $0.action == .move }.map(\.hit.path)
        let alert = NSAlert()
        alert.messageText = String(format: L("tray.confirm.title"), tray.count, bytesText(trayBytes))
        alert.informativeText = String(format: L("tray.confirm.detail"), toTrash.count, toMove.count)
        alert.addButton(withTitle: L("tray.apply"))
        alert.addButton(withTitle: L("action.cancel"))
        guard alert.runFront() == .alertFirstButtonReturn else { return }
        var folder: URL?
        if !toMove.isEmpty {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = L("tray.moveHere")
            guard panel.runFront() == .OK, let url = panel.url else { return }
            folder = url
        }
        undo?.beginUndoGrouping()
        trashPaths(toTrash, undo: undo)
        if let folder { movePaths(toMove, to: folder, undo: undo) }
        undo?.endUndoGrouping()
        undo?.setActionName(L("tray.apply"))
        clearTray()
    }

    /// Move files into a folder off the main thread (a move to another drive
    /// copies the whole file), undoable, then tell the engine.
    func moveInBackground(_ paths: [String], to folder: URL, undo: UndoManager?) {
        notice = String(format: L("notice.moving"), paths.count)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var moved: [(from: URL, to: URL)] = []
            for path in paths {
                let from = URL(fileURLWithPath: path)
                var to = folder.appendingPathComponent(from.lastPathComponent)
                var n = 2
                while FileManager.default.fileExists(atPath: to.path) {
                    let base = from.deletingPathExtension().lastPathComponent, ext = from.pathExtension
                    to = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                    n += 1
                }
                if (try? FileManager.default.moveItem(at: from, to: to)) != nil { moved.append((from, to)) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let gone = Set(moved.map(\.from.path))
                self.results.removeAll { gone.contains($0.path) }
                self.selection.subtract(gone)
                self.notice = String(format: L("notice.moved"), moved.count)
                if moved.count < paths.count {
                    self.trouble = String(format: L("notice.movedSome"), moved.count, paths.count - moved.count)
                }
                if !moved.isEmpty {
                    undo?.registerUndo(withTarget: self) { m in
                        let back = moved
                        DispatchQueue.global(qos: .userInitiated).async {
                            for b in back { try? FileManager.default.moveItem(at: b.to, to: b.from) }
                            DispatchQueue.main.async { m.tellEngine(back.flatMap { [$0.from, $0.to] }); m.schedule(now: true, keepSelection: true) }
                        }
                    }
                    undo?.setActionName(L("drive.moveHere.button"))
                }
                self.tellEngine(moved.flatMap { [$0.from, $0.to] })
            }
        }
    }

    /// Move files into a folder (a new name when one is taken), undoable.
    func movePaths(_ paths: [String], to folder: URL, undo: UndoManager?) {
        var moved: [(from: URL, to: URL)] = []
        for path in paths {
            let from = URL(fileURLWithPath: path)
            var to = folder.appendingPathComponent(from.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: to.path) {
                let base = from.deletingPathExtension().lastPathComponent
                let ext = from.pathExtension
                to = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            if (try? FileManager.default.moveItem(at: from, to: to)) != nil { moved.append((from, to)) }
        }
        let gone = Set(moved.map(\.from.path))
        results.removeAll { gone.contains($0.path) }
        selection.subtract(gone)
        notice = String(format: L("notice.moved"), moved.count)
        if moved.count < paths.count {
            trouble = String(format: L("notice.movedSome"), moved.count, paths.count - moved.count)
        }
        undo?.registerUndo(withTarget: self) { model in
            for m in moved { try? FileManager.default.moveItem(at: m.to, to: m.from) }
            model.tellEngine(moved.map(\.from) + moved.map(\.to))
            model.schedule(now: true, keepSelection: true)
        }
        tellEngine(moved.map(\.from) + moved.map(\.to))
    }

    // MARK: review mode

    func startReview() {
        guard !results.isEmpty else { return }
        sweep = nil
        let first = results.firstIndex { selection.contains($0.path) } ?? 0
        reviewIndex = first
        selectOne(results[first].path)
    }

    /// K, T, M in review mode: keep (takes it out of the tray), or mark for
    /// the Trash or a folder; then the next file.
    func reviewDecide(_ action: TrayAction?) {
        let items = reviewItems
        guard let i = reviewIndex, items.indices.contains(i) else { return }
        let h = items[i]
        if let action { mark([h], action) } else { unmark([h.path]) }
        reviewStep(1)
    }

    /// The folders changed: the engine lists them again at once.
    func tellEngine(_ urls: [URL]) {
        let folders = Set(urls.map { $0.deletingLastPathComponent().path })
        let engine = self.engine
        DispatchQueue.global(qos: .utility).async { folders.forEach { engine.touched(folder: $0) } }
    }
}

enum TrayAction: String { case trash, move }

struct TrayItem {
    let hit: Hit
    let action: TrayAction
}
