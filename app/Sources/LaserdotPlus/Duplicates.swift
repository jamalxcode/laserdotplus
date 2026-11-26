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
    @Published var similar = true
    /// Paths the user chose to keep (starts as the engine's recommendation).
    @Published var keep: Set<String> = []
    @Published var problem: String?
    @Published var summary: String?

    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var toRemove: [DuplicateFile] { groups.flatMap { g in g.files.filter { !keep.contains($0.path) } } }
    var bytesToFree: UInt64 { toRemove.reduce(0) { $0 + $1.size } }

    func scan(scope: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        problem = nil
        summary = nil
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
            }
        }
    }

    /// Keep or let go of one copy; the last kept copy of a group stays.
    func toggle(_ f: DuplicateFile, in g: DuplicateGroup) {
        if keep.contains(f.path) {
            if g.files.filter({ keep.contains($0.path) }).count > 1 { keep.remove(f.path) }
        } else {
            keep.insert(f.path)
        }
    }

    /// The copies not kept go to the Trash, after a preview.
    func moveToTrash(then done: @escaping () -> Void) {
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
                    let outcome = Result { try engine.cleanup(sets: sets, folder: nil) }
                    DispatchQueue.main.async {
                        switch outcome {
                        case let .success(o):
                            let gone = Set(o.movedPaths)
                            self.groups = self.groups.map { g in
                                DuplicateGroup(kind: g.kind, files: g.files.filter { !gone.contains($0.path) }, reclaimable: 0)
                            }.filter { $0.files.count > 1 }
                            self.summary = String(format: L("dupes.done"), o.moved, bytesText(o.bytes))
                                + (o.skipped.isEmpty ? "" : " " + String(format: L("dupes.confirm.skipped"), o.skipped.count))
                        case let .failure(e):
                            self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                        }
                        self.phase = .done
                        done()
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

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "square.on.square", title: L("dupes.title"), detail: model.placeTitle,
                       done: { model.showDupes = false }) {
                Toggle(L("dupes.similar"), isOn: $dupes.similar).toggleStyle(.checkbox)
                Button(dupes.phase == .idle ? L("dupes.find") : L("dupes.again")) { dupes.scan(scope: model.dupesScope) }
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
                    Button(String(format: L("dupes.trashN"), countText(dupes.toRemove.count, "copy"), bytesText(dupes.bytesToFree))) {
                        dupes.moveToTrash { model.schedule(now: true, keepSelection: true) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(dupes.toRemove.isEmpty || dupes.phase != .done)
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var content: some View {
        switch dupes.phase {
        case .idle:
            message("square.on.square", L("dupes.intro"))
        case .scanning:
            VStack(spacing: 10) {
                ProgressView()
                Text(L("dupes.scanning")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private func message(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func group(_ g: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("dupes.kind." + g.kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(g.files, id: \.path) { f in
                let kept = dupes.keep.contains(f.path)
                HStack(spacing: 8) {
                    // One control: the mark and its word together.
                    HStack(spacing: 4) {
                        Image(systemName: kept ? "checkmark.circle.fill" : "trash.circle")
                            .font(.title3)
                        Text(kept ? L("dupes.keep") : L("dupes.trashOne")).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(kept ? Color.green : Color.red)
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
