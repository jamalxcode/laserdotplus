import AppKit
import LaserdotKit
import SwiftUI

/// Clean Up (the owner: "clean out junk, remove duplicates to save space"):
/// one screen over the files with three kinds of clean-up for the current
/// place — Duplicates, Junk (system files, unfinished downloads, empty files
/// and folders) and Big & old (large files untouched for years) — each with
/// the space it frees and one Move to Trash (never deletes; Edit ▸ Undo).
enum CleanupTab: String, CaseIterable { case duplicates, junk, bigOld }

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

    func scan(roots: [String]) {
        guard phase != .scanning else { return }
        phase = .scanning
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [JunkItem] = []
            for r in roots { found += (try? engine.junk(path: r)) ?? [] }
            DispatchQueue.main.async {
                self?.items = found
                self?.chosen = Set(found.map(\.path)) // junk: all ticked
                self?.phase = .done
            }
        }
    }
}

/// Big & old: from the index (a search), so it is quick on any drive.
final class BigOldModel: ObservableObject {
    enum Phase { case idle, scanning, done }
    @Published var phase = Phase.idle
    @Published var items: [Hit] = []
    @Published var chosen: Set<String> = []
    @Published var minMB = 500
    @Published var years = 2
    static let sizes = [100, 500, 1000, 5000]
    static let ages = [1, 2, 5]
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var chosenBytes: UInt64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size } }

    func scan(place: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        let size = minMB >= 1000 ? "fsize:>\(minMB / 1000)gb" : "fsize:>\(minMB)mb"
        let q = [place, size, "before:\(years)y", "-kind:folder"].filter { !$0.isEmpty }.joined(separator: " ")
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hits = (try? engine.search(query: q, limit: 2000, sort: .size, reverse: false))?.hits ?? []
            DispatchQueue.main.async {
                self?.items = hits.sorted { $0.size > $1.size }
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
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.top, 10)
            switch model.cleanupTab {
            case .duplicates: DuplicatesView(model: model, dupes: model.dupes)
            case .junk: junkView
            case .bigOld: bigView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            switch junk.phase {
            case .idle: message("trash.slash", L("cleanup.junk.intro"))
            case .scanning: busy(L("cleanup.junk.scanning"))
            case .done:
                if junk.items.isEmpty {
                    message("checkmark.circle", L("cleanup.junk.none"))
                } else {
                    List(junk.items, id: \.path) { j in
                        row(path: j.path, size: j.size, note: L("cleanup.why." + j.why),
                            chosen: junk.chosen.contains(j.path), isDir: j.why == "empty_folder") {
                            if junk.chosen.contains(j.path) { junk.chosen.remove(j.path) } else { junk.chosen.insert(j.path) }
                        }
                    }
                    footer(count: junk.chosen.count, bytes: junk.chosenBytes) {
                        let paths = Array(junk.chosen)
                        model.trashPaths(paths, undo: undo)
                        junk.items.removeAll { paths.contains($0.path) }
                        junk.chosen = []
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
                Picker(L("cleanup.untouched"), selection: $big.years) {
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
                        row(path: h.path, size: h.size, note: dateText(h.modified),
                            chosen: big.chosen.contains(h.path), isDir: false) {
                            if big.chosen.contains(h.path) { big.chosen.remove(h.path) } else { big.chosen.insert(h.path) }
                        }
                    }
                    footer(count: big.chosen.count, bytes: big.chosenBytes) {
                        let paths = Array(big.chosen)
                        model.trashPaths(paths, undo: undo)
                        big.items.removeAll { paths.contains($0.path) }
                        big.chosen = []
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
        .onTapGesture(perform: toggle)
        .contextMenu {
            Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
    }

    private func footer(count: Int, bytes: UInt64, trash: @escaping () -> Void) -> some View {
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
            .disabled(count == 0)
        }
        .padding(10)
    }

    private func message(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
