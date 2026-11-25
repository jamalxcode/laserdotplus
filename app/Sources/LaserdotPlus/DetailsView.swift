import LaserdotKit
import SwiftUI

/// Everything about the selected file: a large preview (move the pointer
/// across a video to flip through it), a storyboard of twelve frames for
/// videos, and what the engine reads from the file — tracks, languages,
/// camera, tags, a data file's columns. Several selected: how many, how big.
struct DetailsView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        Group {
            let hits = model.selectedHits
            if hits.count == 1, let h = hits.first {
                one(h)
            } else if hits.count > 1 {
                many(hits)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("details.none")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func one(_ h: Hit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if h.kind == "video" {
                        ScrubThumb(path: h.path, size: 260)
                    } else {
                        FileIcon(path: h.path, size: 240, thumbnail: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .onTapGesture(count: 2) { model.open([h]) }
                Text(h.name).font(.headline).textSelection(.enabled)
                actions([h])
                if h.kind == "video" {
                    Storyboard(path: h.path)
                }
                facts(h)
                if let d = model.details, d.path == h.path {
                    ForEach(d.sections, id: \.id) { s in section(s) }
                } else if h.kind == "video" || h.kind == "audio" || h.kind == "image" || h.kind == "document" {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(14)
        }
    }

    private func many(_ hits: [Hit]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: L("results.selected"), hits.count, bytesText(hits.reduce(0) { $0 + $1.size })))
                .font(.headline)
            actions(hits)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(_ hits: [Hit]) -> some View {
        HStack {
            Button(L("action.open")) { model.open(hits) }
            Button(L("action.reveal")) { model.reveal(hits) }
            Button(role: .destructive) { model.trash(hits, undo: undo) } label: { Image(systemName: "trash") }
                .help(L("action.trash"))
        }
        .controlSize(.small)
    }

    private func facts(_ h: Hit) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            row(L("details.kind"), kindText(h.kind))
            if !h.isDir { row(L("details.size"), bytesText(h.size)) }
            row(L("details.modified"), dateText(h.modified))
            if h.created > 0 && h.created != h.modified { row(L("details.created"), dateText(h.created)) }
            row(L("details.where"), whereText(h.path))
        }
        .font(.callout)
    }

    private func section(_ s: DetailSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title("details.section." + s.id, s.id)).font(.callout.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                    row(title("details.key." + r.key, r.key), value(r.value))
                }
            }
            .font(.callout)
        }
        .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3)
        }
    }

    private func title(_ key: String, _ fallback: String) -> String {
        let s = L(key)
        return s == key ? fallback : s
    }

    private func value(_ v: String) -> String { v == "yes" ? L("details.yes") : v }
}

/// Twelve frames across a video, to tell what it is at a glance (frames are
/// read off the main thread, a few at a time, and kept in memory only).
struct Storyboard: View {
    let path: String
    @State private var frames: [Int: NSImage] = [:]
    @State private var framesFor = ""
    private static let count = 12

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(0..<Self.count, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                    if framesFor == path, let img = frames[i] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .task(id: path) {
            frames = [:]
            framesFor = path
            for i in 0..<Self.count {
                if Task.isCancelled { return }
                let at = (Double(i) + 0.5) / Double(Self.count)
                if let img = await VideoFrames.frame(path, at: at, edge: 120), !Task.isCancelled {
                    frames[i] = img
                }
            }
        }
    }
}
