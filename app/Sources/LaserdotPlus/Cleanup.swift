import AppKit
import LaserdotKit
import SwiftUI

/// Clean Up (the owner: "clean out junk, remove duplicates to save space"):
/// one screen over the files with three kinds of clean-up for the current
/// place — Duplicates, Junk (system files, unfinished downloads, empty files
/// and folders) and Big & old (large files untouched for years) — each with
/// the space it frees and one Move to Trash (never deletes; Edit ▸ Undo).
enum CleanupTab: String, CaseIterable { case duplicates, junk, bigOld, space, broken, unwanted }

/// Junk: found by the engine walking the place's folders (junk is never
/// indexed, so no search finds it).
final class JunkModel: ObservableObject {
    enum Phase { case idle, scanning, done }
    @Published var phase = Phase.idle
    @Published var items: [JunkItem] = []
    @Published var chosen: Set<String> = []
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var chosenBytes: UInt64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size } }

    /// While walking: folders gone through and the one it is in.
    @Published var folders: UInt64 = 0
    @Published var current = ""
    private var poll: Timer?
    private var earlier: [JunkItem] = [] // finished roots' finds (several roots)
    private var stopped = false
    /// What the index already knew (shown at once); the walk adds to it.
    private var known: [JunkItem] = []
    /// The running root's finds so far, fetched a piece at a time.
    private var live: [JunkItem] = []

    func scan(roots: [String]) {
        guard phase != .scanning else { return }
        phase = .scanning
        items = []
        chosen = []
        earlier = []
        live = []
        known = []
        stopped = false
        folders = 0
        current = ""
        let engine = self.engine
        // What is found shows as it is found (the owner: "show results as soon
        // as something is found rather than finish the whole drive").
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.phase == .scanning else { return }
            let from = self.live.count
            DispatchQueue.global(qos: .utility).async {
                guard let p = engine.junkFound(from: from), p.running else { return }
                DispatchQueue.main.async {
                    guard self.phase == .scanning else { return }
                    if p.from == self.live.count { self.live += p.items } // only what is new
                    if p.total < self.live.count { self.live = [] } // the next root's walk began
                    if !p.items.isEmpty { self.take(self.earlier + self.live) }
                    self.folders = p.folders
                    self.current = p.current
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // First what the index knows — empty files and folders, old
            // partial downloads — at once (the critique: the walk of an 8 TB
            // drive takes long); the walk goes on for the system files.
            let indexed = roots.flatMap { engine.junkIndexed(path: $0) }
            DispatchQueue.main.async {
                guard let self, self.phase == .scanning else { return }
                self.known = indexed
                self.take([])
            }
            var found: [JunkItem] = []
            for r in roots {
                if DispatchQueue.main.sync(execute: { self?.stopped ?? true }) { break }
                found += (try? engine.junk(path: r)) ?? []
                let sofar = found
                DispatchQueue.main.async { self?.earlier = sofar; self?.live = [] }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.poll?.invalidate()
                self.take(found)
                self.items.sort { $0.size > $1.size }
                self.phase = .done
            }
        }
    }

    /// Show these, ticking new ones (junk: all ticked) and keeping the
    /// user's untickings.
    /// Built aside and set once (the owner's 8 TB drive: ticking tens of
    /// thousands of finds one at a time copied the whole set each time and
    /// froze the window for 20 seconds).
    private func take(_ found: [JunkItem]) {
        FreezeWatch.mark("junk finds")
        // The index's finds and the walk's, once each.
        var seen = Set<String>()
        let all = (known + found).filter { seen.insert($0.path).inserted }
        let shown = Set(items.map(\.path))
        var next = chosen
        for j in all where !shown.contains(j.path) { next.insert(j.path) }
        items = all
        chosen = next
    }

    func stop() {
        stopped = true
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { engine.stopJunk() }
    }
}

/// Big & old: from the index (a search), so it is quick on any drive.
final class BigOldModel: ObservableObject {
    enum Phase { case idle, scanning, done }
    @Published var phase = Phase.idle
    @Published var items: [Hit] = []
    @Published var chosen: Set<String> = []
    @Published var minMB = (UserDefaults.standard.object(forKey: "bigOld.minMB") as? Int) ?? 500 {
        didSet { UserDefaults.standard.set(minMB, forKey: "bigOld.minMB") }
    }
    @Published var years = (UserDefaults.standard.object(forKey: "bigOld.years") as? Int) ?? 2 {
        didSet { UserDefaults.standard.set(years, forKey: "bigOld.years") }
    }
    /// Old by: not changed (modified), or not opened (as macOS records it on
    /// the file; a file with no record counts as never opened).
    @Published var byOpened = UserDefaults.standard.bool(forKey: "bigOld.byOpened") {
        didSet { UserDefaults.standard.set(byOpened, forKey: "bigOld.byOpened") }
    }
    /// Last opened, read from the files found (0: never recorded).
    @Published var opened: [String: Int64] = [:]
    static let sizes = [100, 500, 1000, 5000]
    static let ages = [1, 2, 5]
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var chosenBytes: UInt64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size } }

    func scan(place: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        let size = minMB >= 1000 ? "fsize:>\(minMB / 1000)gb" : "fsize:>\(minMB)mb"
        let age = byOpened ? "" : "before:\(years)y"
        let q = [place, size, age, "-kind:folder"].filter { !$0.isEmpty }.joined(separator: " ")
        let (engine, wantOpened, ageYears) = (self.engine, self.byOpened, self.years)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var hits: [Hit]
            var opened: [String: Int64] = [:]
            if wantOpened {
                // The whole search, oldest-opened first (the engine reads each
                // file's date), kept while older than the cut-off.
                let cutoff = Int64(Date().addingTimeInterval(-Double(ageYears) * 365.25 * 86400).timeIntervalSince1970)
                hits = ((try? engine.byOpened(query: q, limit: 20_000, reverse: true))?.hits ?? []).filter { $0.opened < cutoff }
                for h in hits { opened[h.path] = h.opened }
            } else {
                hits = (try? engine.search(query: q, limit: 5000, sort: .size, reverse: false))?.hits ?? []
            }
            DispatchQueue.main.async {
                self?.items = hits.sorted { $0.size > $1.size }
                self?.opened = opened
                self?.chosen = [] // big files: the user picks
                self?.phase = .done
            }
        }
    }
}

struct CleanupView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel
    @ObservedObject var junk: JunkModel
    @ObservedObject var big: BigOldModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.cleanupTab) {
                Text(L("cleanup.duplicates")).tag(CleanupTab.duplicates)
                Text(L("cleanup.junk")).tag(CleanupTab.junk)
                Text(L("cleanup.bigOld")).tag(CleanupTab.bigOld)
                Text(L("space.title")).tag(CleanupTab.space)
                Text(L("broken.short")).tag(CleanupTab.broken)
                Text(L("unwanted.short")).tag(CleanupTab.unwanted)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 680)
            .padding(.top, 10)
            switch model.cleanupTab {
            case .duplicates: DuplicatesView(model: model, dupes: model.dupes)
            case .junk: junkView
            case .bigOld: bigView
            case .space: SpaceView(model: model, space: model.space, root: spaceRoot)
            case .broken:
                BrokenView(model: model, broken: model.broken, row: { p, s, n, c, t in AnyView(row(path: p, size: s, note: n, chosen: c, isDir: false, toggle: t)) },
                           footer: { c, b, t in AnyView(footer(count: c, bytes: b, trash: t)) })
            case .unwanted:
                UnwantedView(model: model, unwanted: model.unwanted, row: { p, s, n, c, t in AnyView(row(path: p, size: s, note: n, chosen: c, isDir: false, toggle: t)) },
                             footer: { c, b, t in AnyView(footer(count: c, bytes: b, trash: t)) })
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Where Space starts: the drive, or every indexed folder.
    private var spaceRoot: String {
        if case let .drive(name) = model.place, let d = drives.drives.first(where: { $0.name == name }) { return d.mount }
        return ""
    }

    /// The folders junk is looked for in: the drive's, this Mac's, or all.
    private var junkRoots: [String] {
        switch model.place {
        case .everywhere: return [""]
        case .thisMac: return model.status?.folders ?? []
        case let .drive(name): return drives.drives.first { $0.name == name }.map { [$0.mount] } ?? []
        }
    }

    // MARK: Junk

    private var junkView: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "trash.slash", title: L("cleanup.junk"), detail: model.placeTitle, done: { model.showDupes = false }) {
                Button(junk.phase == .idle ? L("cleanup.find") : L("dupes.again")) { junk.scan(roots: junkRoots) }
                    .disabled(junk.phase == .scanning)
            }
            Divider()
            if junk.phase == .scanning {
                // How far it has got, what it is reading, and Stop.
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(String(format: L("cleanup.junk.progress"), junk.folders)).monospacedDigit()
                    Text((junk.current as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if !junk.items.isEmpty {
                        Text(String(format: L("dupes.soFar"), countText(junk.items.count, "file"))).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L("dupes.stop")) { junk.stop() }.help(L("cleanup.junk.stop.help"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.07))
            }
            switch junk.phase {
            case .idle: message("trash.slash", L("cleanup.junk.intro"))
            case .scanning where junk.items.isEmpty: busy(L("cleanup.junk.scanning"))
            case .scanning, .done:
                if junk.items.isEmpty {
                    message("checkmark.circle", L("cleanup.junk.none"))
                } else {
                    List(junk.items, id: \.path) { j in
                        row(path: j.path, size: j.size, note: L("cleanup.why." + j.why),
                            chosen: junk.chosen.contains(j.path), isDir: j.why == "empty_folder") {
                            if junk.chosen.contains(j.path) { junk.chosen.remove(j.path) } else { junk.chosen.insert(j.path) }
                        }
                    }
                    footer(count: junk.chosen.count, bytes: junk.chosenBytes, enabled: junk.phase == .done) {
                        // Off the main thread: thousands of files must not freeze the window.
                        let paths = Array(junk.chosen)
                        model.trashInBackground(paths, undo: undo) { gone, _ in
                            junk.items.removeAll { gone.contains($0.path) }
                            junk.chosen.subtract(gone)
                        }
                    }
                }
            }
        }
    }

    // MARK: Big & old

    private var bigView: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "externaldrive.badge.timemachine", title: L("cleanup.bigOld"), detail: model.placeTitle,
                       done: { model.showDupes = false }) {
                Picker(L("dupes.larger"), selection: $big.minMB) {
                    ForEach(BigOldModel.sizes, id: \.self) { mb in Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb) }
                }
                .fixedSize()
                Picker("", selection: $big.byOpened) {
                    Text(L("cleanup.notChanged")).tag(false)
                    Text(L("cleanup.notOpened")).tag(true)
                }
                .labelsHidden()
                .fixedSize()
                Picker(L("cleanup.for"), selection: $big.years) {
                    ForEach(BigOldModel.ages, id: \.self) { y in Text(String(format: L("cleanup.years"), y)).tag(y) }
                }
                .fixedSize()
                Button(big.phase == .idle ? L("cleanup.find") : L("dupes.again")) { big.scan(place: model.dupesScope) }
                    .disabled(big.phase == .scanning)
            }
            Divider()
            switch big.phase {
            case .idle: message("externaldrive.badge.timemachine", L("cleanup.big.intro"))
            case .scanning: busy(L("cleanup.big.scanning"))
            case .done:
                if big.items.isEmpty {
                    message("checkmark.circle", L("cleanup.big.none"))
                } else {
                    List(big.items, id: \.path) { h in
                        row(path: h.path, size: h.size, note: big.byOpened
                            ? (big.opened[h.path].flatMap { $0 > 0 ? String(format: L("bar.opened"), dateText($0)) : nil } ?? L("cleanup.neverOpened"))
                            : String(format: L("bar.modified"), dateText(h.modified)),
                            chosen: big.chosen.contains(h.path), isDir: false) {
                            if big.chosen.contains(h.path) { big.chosen.remove(h.path) } else { big.chosen.insert(h.path) }
                        }
                    }
                    footer(count: big.chosen.count, bytes: big.chosenBytes) {
                        // Off the main thread: thousands of files must not freeze the window.
                        let paths = Array(big.chosen)
                        model.trashInBackground(paths, undo: undo) { gone, _ in
                            big.items.removeAll { gone.contains($0.path) }
                            big.chosen.subtract(gone)
                        }
                    }
                }
            }
        }
    }

    // MARK: pieces

    private func row(path: String, size: UInt64, note: String, chosen: Bool, isDir: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chosen ? "checkmark.square.fill" : "square")
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle) // the box ticks; the row shows the file
            FileIcon(path: path, size: 24, thumbnail: !isDir)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(whereText(path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(note).font(.caption).foregroundStyle(.secondary)
            Text(isDir ? "" : bytesText(size)).font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.inspect(path, size: size) }
        .background(model.selection == [path] ? Color.accentColor.opacity(0.15) : Color.clear)
        .contextMenu {
            Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
    }

    /// `enabled` false while a walk still runs (Stop ends it at once).
    private func footer(count: Int, bytes: UInt64, enabled: Bool = true, trash: @escaping () -> Void) -> some View {
        HStack {
            Text(String(format: L("cleanup.chosen"), countText(count, "file"), bytesText(bytes))).foregroundStyle(.secondary)
            Spacer()
            Button(String(format: L("cleanup.trash"), countText(count, "file"), bytesText(bytes))) {
                let a = NSAlert()
                a.messageText = String(format: L("cleanup.confirm"), countText(count, "file"), bytesText(bytes))
                a.informativeText = L("dupes.confirm.help")
                a.addButton(withTitle: L("dupes.trash"))
                a.addButton(withTitle: L("action.cancel"))
                if a.runFront() == .alertFirstButtonReturn { trash() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(count == 0 || !enabled)
        }
        .padding(10)
    }

    /// macOS's own empty-state look (symbol, then the words).
    private func message(_ symbol: String, _ text: String) -> some View {
        ContentUnavailableView {
            Image(systemName: symbol)
        } description: {
            Text(text)
        }
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
