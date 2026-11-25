import LaserdotKit
import SwiftUI

/// Big pictures: photos and videos (move the pointer across a video to flip
/// through it), every other file by its icon. Click selects, ⌘ adds, ⇧
/// selects a range, a double click opens; drag across the tiles to select
/// them with a box.
struct ResultsGrid: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo
    @State private var anchor: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.tileSize + 24), spacing: 10)], spacing: 12) {
                    ForEach(Array(model.results.enumerated()), id: \.element.path) { i, h in
                        tile(i, h)
                    }
                }
                .padding(12)
                if model.canLoadMore {
                    Button(L("results.more")) { model.loadMore() }.padding(.bottom, 12)
                }
            }
            .marqueeSelect(model)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { model.selection = [] }
    }

    private func tile(_ i: Int, _ h: Hit) -> some View {
        let selected = model.selection.contains(h.path)
        let size = model.tileSize
        return VStack(spacing: 4) {
            Group {
                if h.kind == "video" {
                    ScrubThumb(path: h.path, size: size)
                } else {
                    FileIcon(path: h.path, size: size, thumbnail: h.kind == "image" || h.kind == "document")
                        .frame(width: size + 8, height: size * 0.92)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            Text(h.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.white : Color.primary)
            if let b = h.badges.first {
                Text(b).font(.caption2).foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(6)
        .frame(width: size + 24, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open([h]) }
        .onTapGesture { anchor = model.click(i, h, anchor: anchor) }
        .contextMenu { FileMenu(model: model, hits: model.targets(h.path), undo: undo) }
        .tileFrame(h.path)
        .fileDrag(h.path, when: selected)
    }
}
