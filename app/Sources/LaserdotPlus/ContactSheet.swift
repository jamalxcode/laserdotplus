import LaserdotKit
import SwiftUI

/// The contact sheet: one row per file — a strip of eight frames for a
/// video (to tell films apart at a glance), the picture for a photo, the
/// icon otherwise — with its name and details. Frames load only for rows
/// that stay on screen, a few at a time.
struct ContactSheet: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo
    @State private var anchor: Int?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.results.enumerated()), id: \.element.path) { i, h in
                    row(i, h)
                }
                if model.canLoadMore {
                    Button(L("results.more")) { model.loadMore() }.padding(8)
                }
            }
            .padding(8)
            .marqueeSelect(model)
        }
    }

    private func row(_ i: Int, _ h: Hit) -> some View {
        let selected = model.selection.contains(h.path)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(h.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(h.badges.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(bytesText(h.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if h.kind == "video" {
                FrameStrip(path: h.path, count: 8, height: model.tileSize * 0.45)
            } else {
                FileIcon(path: h.path, size: model.tileSize * 0.45, thumbnail: h.kind == "image" || h.kind == "document")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open([h]) }
        .onTapGesture { anchor = model.click(i, h, anchor: anchor) }
        .contextMenu { FileMenu(model: model, hits: model.targets(h.path), undo: undo) }
        .tileFrame(h.path)
        .fileDrag(h.path, when: selected)
    }
}

/// `count` frames across a video, side by side.
struct FrameStrip: View {
    let path: String
    let count: Int
    let height: CGFloat
    @State private var frames: [Int: NSImage] = [:]
    @State private var framesFor = ""

    var body: some View {
        // Each frame gets an equal share of the row's width: never wider.
        GeometryReader { g in
            let w = max(10, (g.size.width - CGFloat(count - 1) * 3) / CGFloat(count))
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.12))
                        if framesFor == path, let img = frames[i] {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: w, height: height)
                        }
                    }
                    .frame(width: w, height: height)
                    .clipped()
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: path) {
            frames = [:]
            framesFor = path
            try? await Task.sleep(nanoseconds: 200_000_000) // not for rows passing by
            for i in 0..<count {
                if Task.isCancelled { return }
                let at = (Double(i) + 0.5) / Double(count)
                if let img = await VideoFrames.frame(path, at: at, edge: max(80, height * 1.6)), !Task.isCancelled {
                    frames[i] = img
                }
            }
        }
    }
}

/// The timeline: the files by month (newest first), each month a band of
/// thumbnails with how many and how big.
struct TimelineView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo
    @State private var anchor: Int?

    var body: some View {
        let months = model.months
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                ForEach(months, id: \.id) { m in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: model.tileSize * 0.7 + 12), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(m.items) { item in tile(item.index, item.hit) }
                        }
                    } header: {
                        HStack {
                            Text(m.title).font(.headline)
                            Text(String(format: L("timeline.month"), m.items.count, bytesText(m.bytes)))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                if model.canLoadMore {
                    Button(L("results.more")) { model.loadMore() }.padding(8)
                }
            }
            .padding(10)
            .marqueeSelect(model)
        }
    }

    private func tile(_ i: Int, _ h: Hit) -> some View {
        let selected = model.selection.contains(h.path)
        let size = model.tileSize * 0.7
        return VStack(spacing: 2) {
            if h.kind == "video" {
                ScrubThumb(path: h.path, size: size)
            } else {
                FileIcon(path: h.path, size: size, thumbnail: h.kind == "image" || h.kind == "document")
            }
            Text(h.name).font(.caption2).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .padding(4)
        .frame(width: size + 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open([h]) }
        .onTapGesture { anchor = model.click(i, h, anchor: anchor) }
        .contextMenu { FileMenu(model: model, hits: model.targets(h.path), undo: undo) }
        .tileFrame(h.path)
        .fileDrag(h.path, when: selected)
    }
}

/// One month of the timeline.
struct MonthGroup {
    let id: String
    let title: String
    let items: [IndexedHit]
    let bytes: UInt64
}

/// A result and its place in the list.
struct IndexedHit: Identifiable {
    let index: Int
    let hit: Hit
    var id: String { hit.path }
}
