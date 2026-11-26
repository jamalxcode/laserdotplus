import AppKit
import LaserdotKit
import SwiftUI

/// Clean Up ▸ Space: where the space goes (the critique: finding duplicates
/// and junk does not say which folders are big). The place's folders,
/// biggest first, measured from the index (no disk is read); click a folder
/// to go inside, the path above goes back.
final class SpaceModel: ObservableObject {
    @Published var path: String = ""
    @Published var items: [Wire.StorageItem] = []
    @Published var loading = false
    @Published var problem: String?
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    func load(_ p: String) {
        path = p
        loading = true
        problem = nil
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = Result { try engine.storage(path: p, limit: 60) }
            DispatchQueue.main.async {
                guard let self, self.path == p else { return }
                self.loading = false
                switch r {
                case let .success(rep): self.items = rep.items.sorted { $0.bytes > $1.bytes }
                case let .failure(e):
                    self.items = []
                    self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                }
            }
        }
    }
}

struct SpaceView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var space: SpaceModel
    /// Where this place starts ("" = every indexed folder).
    let root: String

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "chart.bar.xaxis", title: L("space.title"), detail: model.placeTitle,
                       done: { model.showDupes = false }) {
                if space.path != root {
                    Button { space.load(Self.parent(space.path, root: root)) } label: {
                        Label(L("space.up"), systemImage: "chevron.up")
                    }
                }
            }
            Divider()
            if space.path != root {
                Text(friendlyPath(space.path)).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 4)
            }
            if space.loading && space.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let p = space.problem {
                Text(p).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let top = max(1, space.items.first?.bytes ?? 1)
                List(space.items, id: \.path) { it in
                    HStack(spacing: 8) {
                        Image(systemName: it.isDir ? "folder.fill" : "doc")
                            .foregroundStyle(it.isDir ? Palette.kind("folder") : .secondary)
                            .frame(width: 18)
                        Text(it.name).lineLimit(1).truncationMode(.middle).frame(minWidth: 140, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.place.opacity(0.55))
                                .frame(width: max(2, g.size.width * CGFloat(Double(it.bytes) / Double(top))))
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 10)
                        Text(bytesText(it.bytes) + (it.partial ? "+" : "")).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Text(it.isDir ? countText(Int(it.files), "file") : "").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if it.isDir { space.load(it.path) } }
                    .contextMenu {
                        Button(L("action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: it.path)]) }
                        if it.isDir {
                            Button(L("space.showFiles")) {
                                model.text = "in:\"\(it.path)\""
                                model.showDupes = false
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .onAppear { if space.items.isEmpty || !space.path.hasPrefix(root) { space.load(root) } }
        .onChange(of: root) { _, r in space.load(r) }
    }

    static func parent(_ p: String, root: String) -> String {
        let up = (p as NSString).deletingLastPathComponent
        return up.count < root.count || up == p ? root : up
    }
}
