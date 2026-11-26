import LaserdotKit
import SwiftUI

/// Big pictures: photos and videos (move the pointer across a video to flip
/// through it), every other file by its icon. Click selects, ⌘ adds, ⇧
/// selects a range, a double click opens; drag across the tiles to select
/// them with a box.
struct ResultsGrid: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo

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
                } else if h.isDir {
                    FolderCover(path: h.path, size: size, engine: model.engine)
                        .frame(width: size + 8, height: size * 0.92)
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
            // What it is at a glance: a video's length and resolution, a
            // picture's size, else the file's size.
            Text((h.badges.prefix(2) + (h.isDir ? [] : [bytesText(h.size)])).joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(6)
        .frame(width: size + 24, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .contextMenu { FileMenu(model: model, hits: model.targets(h.path), undo: undo) }
        .tileFrame(h.path)
    }
}

/// A folder shows what it holds: up to four of its pictures (asked of the
/// engine, off the main thread; no folder is read), else its icon.
struct FolderCover: View {
    let path: String
    let size: CGFloat
    let engine: Engine
    @State private var inside: [String] = []

    var body: some View {
        ZStack {
            if inside.isEmpty {
                FileIcon(path: path, size: size, thumbnail: false)
            } else {
                let cell = (size - 6) / 2
                LazyVGrid(columns: [GridItem(.fixed(cell), spacing: 4), GridItem(.fixed(cell), spacing: 4)], spacing: 4) {
                    ForEach(inside, id: \.self) { p in
                        FileIcon(path: p, size: cell, thumbnail: true)
                            .frame(width: cell, height: cell)
                            .clipped()
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill").font(.caption).foregroundStyle(.secondary).padding(4)
                }
            }
        }
        .task(id: path) {
            let q = "in:\"" + path.replacingOccurrences(of: "\"", with: "\\\"") + "\" kind:image"
            let engine = self.engine
            let found = await Task.detached(priority: .utility) {
                (try? engine.search(query: q, limit: 4))?.hits.map(\.path) ?? []
            }.value
            inside = found
        }
    }
}
