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
                PlaceSummary(model: model, dupes: model.dupes)
            }
        }
        // The pane keeps the width it was given whatever it shows: a wider
        // content pushed the split, the files reflowed under the mouse, and a
        // double click opened the file that moved there (the owner).
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .layoutPriority(-1)
    }

    /// A slim pane: the preview takes its width, the details are small.
    private func one(_ h: Hit) -> some View {
        GeometryReader { g in
            let edge = max(120, g.size.width - 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if h.kind == "video" {
                            ScrubThumb(path: h.path, size: edge - 8)
                        } else {
                            FileIcon(path: h.path, size: edge, thumbnail: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture(count: 2) { model.open([h]) }
                    details(h)
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder private func details(_ h: Hit) -> some View {
                Text(h.name).font(.headline).textSelection(.enabled).lineLimit(3)
                actions([h])
                facts(h)
                if h.kind == "video" {
                    Storyboard(path: h.path)
                }
                if let d = model.details, d.path == h.path {
                    // The dates are in the facts above (the owner: they must show).
                    ForEach(d.sections.filter { $0.id != "dates" }, id: \.id) { s in section(s) }
                } else if h.kind == "video" || h.kind == "audio" || h.kind == "image" || h.kind == "document" {
                    ProgressView().controlSize(.small)
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

    /// What it is, where, and every date it carries (the owner: "last opened,
    /// date created, and other file time attributes ... include them"), at
    /// the top. Last opened and date added say "Not recorded" when macOS has
    /// no record of them (a file never opened, or copied by a tool that
    /// does not record it).
    private func facts(_ h: Hit) -> some View {
        let loaded = model.details.flatMap { $0.path == h.path ? $0 : nil }
        let dates = loaded?.sections.first { $0.id == "dates" }?.rows ?? []
        let date = { (key: String) in dates.first { $0.key == key }?.value }
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            row(L("details.kind"), kindText(h.kind))
            if !h.isDir { row(L("details.size"), bytesText(h.size)) }
            row(L("details.where"), whereText(h.path))
            Divider().gridCellColumns(2)
            row(L("details.key.dates.created"), date("dates.created") ?? (h.created > 0 ? dateText(h.created) : L("details.notRecorded")))
            row(L("details.key.dates.modified"), date("dates.modified") ?? dateText(h.modified))
            if loaded != nil {
                row(L("details.key.dates.opened"), date("dates.opened") ?? L("details.notRecorded"))
                row(L("details.key.dates.added"), date("dates.added") ?? L("details.notRecorded"))
                if let c = date("dates.changed") { row(L("details.key.dates.changed"), c) }
            }
        }
    }

    private func section(_ s: DetailSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title("details.section." + s.id, s.id)).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                    row(title("details.key." + r.key, r.key), value(r.value))
                }
            }
        }
        .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            // Titles bigger and bolder, so they show (the owner).
            Text(label).font(.callout.weight(.semibold)).foregroundStyle(.primary).gridColumnAlignment(.trailing)
            Text(value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 2), spacing: 3) {
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

/// Nothing selected: what this place holds (the pane was an empty "select a
/// file"): how many files, how big, what kinds, the biggest folders, and the
/// duplicates found — from the engine's counts, nothing read from disk.
struct PlaceSummary: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var dupes: DupesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("summary.title"), model.placeTitle)).font(.headline)
                    Text(countText(Int(model.total), "file")).foregroundStyle(.secondary)
                    if !model.canLoadMore, !model.results.isEmpty {
                        Text(String(format: L("summary.size"), bytesText(model.results.reduce(0) { $0 + $1.size })))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let kinds = model.groups.first(where: { $0.id == "kind" }), !kinds.options.isEmpty {
                    bars(L("summary.kinds"), kinds.options)
                }
                if let folders = model.groups.first(where: { $0.id == "folder" }), !folders.options.isEmpty {
                    bars(L("summary.folders"), Array(folders.options.sorted { $0.count > $1.count }.prefix(5)))
                }
                if dupes.phase == .done, !dupes.groups.isEmpty {
                    Text(String(format: L("summary.dupes"), countText(dupes.groups.count, "group"), bytesText(dupes.bytesToFree)))
                        .font(.caption)
                }
                Button(L("summary.findDupes")) { model.openCleanup(.duplicates) }
                    .controlSize(.small)
                if case let .drive(name) = model.place {
                    DriveTrashLine(mount: "/Volumes/" + name).id(name)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Okabe–Ito: distinct for colour-blind eyes.
    static let palette: [Color] = [
        Color(red: 0, green: 114 / 255, blue: 178 / 255), Color(red: 230 / 255, green: 159 / 255, blue: 0),
        Color(red: 0, green: 158 / 255, blue: 115 / 255), Color(red: 204 / 255, green: 121 / 255, blue: 167 / 255),
        Color(red: 86 / 255, green: 180 / 255, blue: 233 / 255), Color(red: 213 / 255, green: 94 / 255, blue: 0),
    ]

    /// Counts as short bars, biggest first.
    private func bars(_ title: String, _ options: [RefineOption]) -> some View {
        let top = max(1, options.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(options.filter { $0.count > 0 }.prefix(6).enumerated()), id: \.element.token) { i, o in
                HStack(spacing: 6) {
                    Text(ChoiceBands.label(o)).font(.caption).lineLimit(1).frame(width: 90, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.palette[i % Self.palette.count].opacity(0.6))
                            .frame(width: max(2, g.size.width * CGFloat(o.count) / CGFloat(top)))
                    }
                    .frame(height: 8)
                    Text("\(o.count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}
