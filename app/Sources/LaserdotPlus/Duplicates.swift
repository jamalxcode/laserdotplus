import AppKit
import LaserdotKit
import SwiftUI

/// Find Duplicates (the owner: "there is no find duplicates function"): the
/// engine compares the files of the current place — exact copies, and
/// optionally similar pictures and re-encoded videos — and recommends the
/// best copy of each group to keep. Nothing is deleted: the copies not kept
/// go to the Trash, after a preview, and a kept copy that changed meanwhile
/// makes its group skipped. Fingerprints of a drive's files are never kept
/// on this Mac (the engine's rule).
final class DupesModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, done, cleaning }

    @Published var phase = Phase.idle
    @Published var groups: [DuplicateGroup] = []
    @Published var similar = (UserDefaults.standard.object(forKey: "dupes.similar") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(similar, forKey: "dupes.similar") }
    }
    /// Only files larger than this many MB are compared (the owner: "why wait
    /// for every file to be checked when the objective is just to save
    /// storage"): smaller files are never read. 0: every file.
    @Published var minMB: Int = (UserDefaults.standard.object(forKey: "dupes.minMB") as? Int) ?? 100 {
        didSet {
            UserDefaults.standard.set(minMB, forKey: "dupes.minMB")
            // Big files: comparing frames of every video is the slow part;
            // exact copies are where the space is. (It can be ticked again.)
            if minMB >= 1000, oldValue < 1000 { similar = false }
        }
    }
    static let sizes = [0, 10, 100, 1000]

    /// The search the comparison is limited to: the place, and the size.
    func scope(place: String) -> String {
        let size = minMB > 0 ? (minMB >= 1000 ? "fsize:>\(minMB / 1000)gb" : "fsize:>\(minMB)mb") : ""
        return [place, size].filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// Paths the user chose to keep (starts as the engine's recommendation).
    @Published var keep: Set<String> = []
    @Published var problem: String?
    @Published var summary: String?

    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var toRemove: [DuplicateFile] { groups.flatMap { g in g.files.filter { !keep.contains($0.path) } } }
    var bytesToFree: UInt64 { toRemove.reduce(0) { $0 + $1.size } }

    /// How far the scan has got (its step, files done of total, the file
    /// being read), asked every second or so while it runs.
    @Published var progress: Wire.DupeProgress?
    private var poll: Timer?

    /// While scanning: the step and the groups found so far, shown at once.
    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self, self.phase == .scanning else { return }
            let engine = self.engine
            DispatchQueue.global(qos: .utility).async {
                let p = engine.dupeProgress()
                let found = engine.dupesFound().filter { $0.files.count > 1 }
                DispatchQueue.main.async {
                    guard self.phase == .scanning else { return }
                    self.progress = p
                    if !found.isEmpty { self.take(found) }
                }
            }
        }
    }

    /// Show these groups, keeping the user's Keep choices for files already
    /// shown and the engine's recommendation for new ones.
    private func take(_ found: [DuplicateGroup]) {
        FreezeWatch.mark("duplicate finds")
        let shown = Set(groups.flatMap { $0.files.map(\.path) })
        // Built aside and set once: one update, not one per file.
        var next = keep
        for g in found {
            for f in g.files where !shown.contains(f.path) && f.keep { next.insert(f.path) }
            if !g.files.contains(where: { next.contains($0.path) }), let first = g.files.first { next.insert(first.path) }
        }
        groups = found
        keep = next
    }

    // MARK: which copy to keep, for every group at once

    /// How the copy to keep is chosen (the critique: ticking hundreds of
    /// groups one by one is not practical).
    enum KeepRule: Equatable {
        case best, oldest, newest
        /// Keep the copy inside this folder (groups with none there keep
        /// their choice).
        case inFolder(String)
    }

    /// A folder whose files are never put in the Trash: in each group, its
    /// copies are kept, whatever the rule.
    @Published var protected: String?

    func apply(_ rule: KeepRule) {
        var next: Set<String> = []
        for g in groups {
            let pick: DuplicateFile?
            switch rule {
            case .best: pick = g.files.first(where: \.keep) ?? g.files.first
            case .oldest: pick = g.files.min { ($0.modified, $0.path) < ($1.modified, $1.path) }
            case .newest: pick = g.files.max { ($0.modified, $1.path) < ($1.modified, $0.path) }
            case let .inFolder(dir):
                pick = g.files.first { Self.inside($0.path, dir) } ?? g.files.first { keep.contains($0.path) }
            }
            if let pick { next.insert(pick.path) }
            if let p = protected { g.files.filter { Self.inside($0.path, p) }.forEach { next.insert($0.path) } }
        }
        keep = next
    }

    func protect(_ dir: String?) {
        protected = dir
        if let dir { keep.formUnion(groups.flatMap(\.files).filter { Self.inside($0.path, dir) }.map(\.path)) }
    }

    static func inside(_ path: String, _ dir: String) -> Bool {
        path.hasPrefix(dir.hasSuffix("/") ? dir : dir + "/")
    }

    /// Stop early: what was found so far stays.
    func stop() {
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { engine.stopDuplicates() }
    }

    func scan(scope: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        problem = nil
        summary = nil
        groups = []
        progress = nil
        startPolling()
        let (engine, similar) = (self.engine, self.similar)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try engine.findDuplicates(scope: scope, exactOnly: !similar) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case let .success(r):
                    self.groups = r.groups.filter { $0.files.count > 1 }
                    self.keep = Set(self.groups.flatMap { g in g.files.filter(\.keep).map(\.path) })
                    // A group always keeps at least one copy.
                    for g in self.groups where !g.files.contains(where: { self.keep.contains($0.path) }) {
                        if let first = g.files.first { self.keep.insert(first.path) }
                    }
                case let .failure(e):
                    self.groups = []
                    self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                }
                self.phase = .done
                self.poll?.invalidate()
                self.progress = nil
            }
        }
    }

    /// Keep or let go of one copy; the last kept copy of a group stays.
    func toggle(_ f: DuplicateFile, in g: DuplicateGroup) {
        if let p = protected, Self.inside(f.path, p), keep.contains(f.path) { return } // never touched
        if keep.contains(f.path) {
            if g.files.filter({ keep.contains($0.path) }).count > 1 { keep.remove(f.path) }
        } else {
            keep.insert(f.path)
        }
    }

    /// The copies not kept go to the Trash, after a preview. The engine
    /// checks each one (unchanged, not the kept copy) again right before;
    /// macOS's own Trash call then moves them, as Finder does, so they show
    /// in the Trash, Put Back works and ⌘Z brings them back.
    func moveToTrash(model: LibraryModel, undo: UndoManager?, then done: @escaping () -> Void) {
        let sets = groups.map { g in
            CleanupSet(keep: g.files.filter { keep.contains($0.path) }, remove: g.files.filter { !keep.contains($0.path) })
        }.filter { !$0.remove.isEmpty }
        guard !sets.isEmpty else { return }
        let engine = self.engine
        phase = .cleaning
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preview = Result { try engine.cleanupPreview(sets: sets, folder: nil) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard case let .success(p) = preview else {
                    if case let .failure(e) = preview { self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription }
                    self.phase = .done
                    return
                }
                let alert = NSAlert()
                alert.messageText = String(format: L("dupes.confirm"), p.files, bytesText(p.bytes))
                alert.informativeText = p.skipped.isEmpty ? L("dupes.confirm.help")
                    : String(format: L("dupes.confirm.skipped"), p.skipped.count)
                alert.addButton(withTitle: L("dupes.trash"))
                alert.addButton(withTitle: L("action.cancel"))
                guard alert.runFront() == .alertFirstButtonReturn else { self.phase = .done; return }
                DispatchQueue.global(qos: .userInitiated).async {
                    // Checked again now: a file may have changed while the question was up.
                    let fresh = Result { try engine.cleanupPreview(sets: sets, folder: nil) }
                    DispatchQueue.main.async {
                        guard case let .success(f) = fresh else {
                            if case let .failure(e) = fresh { self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription }
                            self.phase = .done
                            return
                        }
                        let sizes = Dictionary(sets.flatMap(\.remove).map { ($0.path, $0.size) }) { a, _ in a }
                        model.trashInBackground(f.paths, undo: undo) { gone, failed in
                            self.groups = self.groups.map { g in
                                DuplicateGroup(kind: g.kind, files: g.files.filter { !gone.contains($0.path) }, reclaimable: 0)
                            }.filter { $0.files.count > 1 }
                            let bytes = gone.reduce(UInt64(0)) { $0 + (sizes[$1] ?? 0) }
                            self.summary = String(format: L("dupes.done"), gone.count, bytesText(bytes))
                                + (f.skipped.isEmpty ? "" : " " + String(format: L("dupes.confirm.skipped"), f.skipped.count))
                                + (failed == 0 ? "" : " " + String(format: L("dupes.failed"), failed))
                            self.phase = .done
                            done()
                        }
                    }
                }
            }
        }
    }
}

/// The duplicates panel, over the files.
struct DuplicatesView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var dupes: DupesModel
    @Environment(\.undoManager) private var undo
    @State private var comparing: CompareItem?

    /// Which copy to keep, for every group at once.
    private var keepMenu: some View {
        Menu(L("dupes.keep")) {
            Button(L("dupes.keep.best")) { dupes.apply(.best) }
            Button(L("dupes.keep.oldest")) { dupes.apply(.oldest) }
            Button(L("dupes.keep.newest")) { dupes.apply(.newest) }
            Button(L("dupes.keep.folder")) { if let d = Self.chooseFolder() { dupes.apply(.inFolder(d)) } }
            Divider()
            if let p = dupes.protected {
                Button(String(format: L("dupes.unprotect"), (p as NSString).lastPathComponent)) { dupes.protect(nil) }
            } else {
                Button(L("dupes.protect")) { if let d = Self.chooseFolder() { dupes.protect(d) } }
            }
        }
        .fixedSize()
        .help(L("dupes.keep.help"))
        .disabled(dupes.phase != .done)
    }

    static func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runFront() == .OK ? panel.url?.resolvingSymlinksInPath().path : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "square.on.square", title: L("dupes.title"), detail: model.placeTitle,
                       done: { model.showDupes = false }) {
                Picker(L("dupes.larger"), selection: $dupes.minMB) {
                    ForEach(DupesModel.sizes, id: \.self) { mb in
                        Text(mb == 0 ? L("dupes.anySize") : mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                    }
                }
                .fixedSize()
                .help(L("dupes.larger.help"))
                Toggle(L("dupes.similar"), isOn: $dupes.similar).toggleStyle(.checkbox)
                Button(dupes.phase == .idle ? L("dupes.find") : L("dupes.again")) { dupes.scan(scope: dupes.scope(place: model.dupesScope)) }
                    .disabled(dupes.phase == .scanning || dupes.phase == .cleaning)
            }
            Divider()
            content
            if !dupes.groups.isEmpty {
                Divider()
                HStack {
                    Text(String(format: L("dupes.summary"), countText(dupes.groups.count, "group"),
                                countText(dupes.toRemove.count, "copy"), bytesText(dupes.bytesToFree)))
                        .foregroundStyle(.secondary)
                    Spacer()
                    keepMenu
                    Button(String(format: L("dupes.trashN"), countText(dupes.toRemove.count, "copy"), bytesText(dupes.bytesToFree))) {
                        dupes.moveToTrash(model: model, undo: undo) { model.schedule(now: true, keepSelection: true) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(dupes.toRemove.isEmpty || dupes.phase != .done)
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $comparing) { c in CompareView(group: c.group, dupes: dupes) }
    }

    @ViewBuilder private var content: some View {
        switch dupes.phase {
        case .idle:
            message("square.on.square", L("dupes.intro"))
        case .scanning:
            VStack(spacing: 0) {
                progressStrip
                if dupes.groups.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L("dupes.scanning")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    groupList // found so far: shown as soon as they are found
                }
            }
        case .cleaning:
            VStack(spacing: 10) {
                ProgressView()
                Text(L("dupes.cleaning")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            if let p = dupes.problem {
                message("exclamationmark.triangle", p)
            } else if dupes.groups.isEmpty {
                message("checkmark.circle", dupes.summary ?? L("dupes.none"))
            } else {
                groupList
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let s = dupes.summary {
                    Text(s).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
                ForEach(Array(dupes.groups.enumerated()), id: \.offset) { _, g in group(g) }
            }
            .padding(10)
        }
    }

    /// The step, how far along, the file being read, and Stop.
    private var progressStrip: some View {
        HStack(spacing: 10) {
            let p = dupes.progress
            Text(L("dupes.phase." + (p?.phase ?? "listing"))).fontWeight(.medium)
            if let p, p.total > 0 {
                ProgressView(value: Double(p.done), total: Double(p.total)).frame(maxWidth: 220)
                Text("\(p.done) / \(p.total)").monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            if let cur = p?.current, !cur.isEmpty {
                Text((cur as NSString).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !dupes.groups.isEmpty {
                Text(String(format: L("dupes.soFar"), countText(dupes.groups.count, "group"))).font(.caption).foregroundStyle(.secondary)
            }
            Button(L("dupes.stop")) { dupes.stop() }
                .help(L("dupes.stop.help"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.07))
    }

    /// macOS's own empty-state look (symbol, then the words).
    private func message(_ symbol: String, _ text: String) -> some View {
        ContentUnavailableView {
            Image(systemName: symbol)
        } description: {
            Text(text)
        }
    }

    private func group(_ g: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("dupes.kind." + g.kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { comparing = CompareItem(group: g) } label: { Label(L("dupes.compare"), systemImage: "rectangle.split.3x1") }
                    .controlSize(.small)
                    .help(L("dupes.compare.help"))
            }
            ForEach(g.files, id: \.path) { f in
                let kept = dupes.keep.contains(f.path)
                HStack(spacing: 8) {
                    // One control: the mark and its word together.
                    HStack(spacing: 4) {
                        Image(systemName: kept ? "checkmark.circle.fill" : "trash.circle")
                            .font(.title3)
                        Text(kept ? L("dupes.keep") : L("dupes.trashOne")).font(.caption.weight(.semibold))
                    }
                    // Okabe–Ito blue and vermillion (colour-blind safe), with the icon and word.
                    .foregroundStyle(kept ? Palette.place : Palette.kind("video"))
                    .frame(width: 74, alignment: .leading)
                    FileIcon(path: f.path, size: 40, thumbnail: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((f.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(whereText(f.path))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    // Without "bpp" (jargon): the size and the rest say enough.
                    Text(f.summary.components(separatedBy: " · ").filter { !$0.hasSuffix("bpp") }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(bytesText(f.size)).font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { dupes.toggle(f, in: g) } // the whole row switches Keep / Trash
                .help(kept ? L("dupes.kept") : L("dupes.goes"))
                .contextMenu {
                    Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

/// One group's copies side by side, to choose which to keep by looking (the
/// critique: choosing from text alone is hard). Quick Look plays them one
/// after another (← →).
struct CompareItem: Identifiable {
    let id = UUID()
    let group: DuplicateGroup
}

struct CompareView: View {
    let group: DuplicateGroup
    @ObservedObject var dupes: DupesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L("dupes.kind." + group.kind)).font(.headline)
                Spacer()
                Button(L("dupes.compare.quickLook")) {
                    QuickLook.shared.toggle(group.files.map { URL(fileURLWithPath: $0.path) }, at: 0)
                }
                Button(L("action.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(group.files, id: \.path) { f in
                        let kept = dupes.keep.contains(f.path)
                        VStack(alignment: .leading, spacing: 6) {
                            Group {
                                if Palette.kind(ofExtension: (f.path as NSString).pathExtension) == "video" {
                                    ScrubThumb(path: f.path, size: 260)
                                } else {
                                    FileIcon(path: f.path, size: 260, thumbnail: true)
                                }
                            }
                            .frame(width: 270, height: 200)
                            Text((f.path as NSString).lastPathComponent).font(.callout.weight(.semibold)).lineLimit(2)
                            Text(whereText(f.path)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(f.summary).font(.caption).lineLimit(2)
                            Text("\(bytesText(f.size)) · \(String(format: L("bar.modified"), dateText(f.modified)))")
                                .font(.caption).foregroundStyle(.secondary)
                            Button { dupes.toggle(f, in: group) } label: {
                                Label(kept ? L("dupes.keep") : L("dupes.trashOne"), systemImage: kept ? "checkmark.circle.fill" : "trash.circle")
                            }
                            .foregroundStyle(kept ? Palette.place : Palette.kind("video"))
                        }
                        .frame(width: 270)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(kept ? Palette.place : Color.secondary.opacity(0.3), lineWidth: kept ? 2 : 1))
                    }
                }
                .padding(4)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }
}
