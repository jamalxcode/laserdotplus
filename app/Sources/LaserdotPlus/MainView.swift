import LaserdotKit
import SwiftUI

/// The window centres on the files (the owner: "the focus to be on the files
/// being reviewed and looked at and arranged, with other functions
/// surrounding it"): a few lines at the top to search (the search box, the
/// view, then places and choices), the files in the middle, a slim pane on
/// the right with the preview and the file's details, and a bottom margin
/// about the selected file. The top area and the right pane are resized by
/// dragging their edges.
struct MainView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        VStack(spacing: 0) {
            // The top hugs what it shows (no empty band above the files); the
            // files and the right pane fill the rest. HSplitView: a plain
            // AppKit split view (resizable, visible to the self-test's captures).
            TopArea(model: model, drives: drives)
            Divider()
            HSplitView {
                FilesArea(model: model, drives: drives)
                    .frame(minWidth: 420, idealWidth: 900, maxWidth: .infinity)
                DetailsView(model: model)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 460)
            }
            .frame(minHeight: 240)
            // Review and Duplicates take the whole width (they were squeezed
            // into the files' half, beside an empty pane).
            .overlay {
                if model.reviewIndex != nil {
                    ReviewView(model: model)
                } else if model.showDupes {
                    DuplicatesView(model: model, dupes: model.dupes)
                }
            }
            if !model.tray.isEmpty {
                Divider()
                TrayBar(model: model)
            }
            Divider()
            BottomBar(model: model, drives: drives)
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch model.place {
        case .everywhere: return "Laserdot+"
        case .thisMac: return "Laserdot+ — " + L("place.thisMac")
        case let .drive(name): return "Laserdot+ — " + name
        }
    }
}

/// The top: the search box and the view controls on one line, then the
/// places and the choice bands (scrolling when the area is made small).
struct TopArea: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel
    /// The choices' natural height: the area is that tall (up to a cap,
    /// then it scrolls), never taller.
    @State private var choicesHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchBox(model: model, drives: drives)
                    .frame(maxWidth: .infinity)
                Picker(L("menu.view"), selection: $model.viewMode) {
                    Image(systemName: "list.bullet").help(L("view.list")).tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").help(L("view.grid")).tag(ViewMode.grid)
                    Image(systemName: "film.stack").help(L("view.sheet")).tag(ViewMode.sheet)
                    Image(systemName: "calendar").help(L("view.timeline")).tag(ViewMode.timeline)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.viewMode != .list {
                    Slider(value: $model.tileSize, in: 96...320)
                        .frame(width: 80)
                        .help(L("view.size"))
                }
                Menu {
                    Picker(L("sort.by"), selection: $model.sort) {
                        ForEach([SortKey.modified, .created, .name, .size, .kind, .relevance], id: \.self) { k in
                            Text(L("sort." + k.rawValue)).tag(k)
                        }
                    }
                    Toggle(L("sort.reverse"), isOn: $model.reverse)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("sort.by"))
                // The modes, apart from the view controls.
                Divider().frame(height: 18).padding(.horizontal, 2)
                // The tools, in one menu (the row was crowded and the search
                // box shrank): each with its shortcut.
                Menu {
                    Button { model.startSweep() } label: { Label(L("sweep.menu"), systemImage: "questionmark.square.dashed") }
                        .keyboardShortcut("e")
                        .disabled(model.results.isEmpty)
                    Button { model.startReview() } label: { Label(L("review.start"), systemImage: "rectangle.stack.badge.play") }
                        .keyboardShortcut("r")
                        .disabled(model.results.isEmpty)
                    Button { model.showDupes = true } label: { Label(L("dupes.menu"), systemImage: "square.on.square") }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                } label: {
                    Label(L("tools.title"), systemImage: "wand.and.stars")
                }
                .fixedSize()
                .help(L("tools.help"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // Where to look: navigation, not a filter — a strip of its own.
            PlacesBar(model: model, drives: drives)
            ScrollView(.vertical) {
                ChoiceBands(model: model)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ChoicesHeightKey.self, value: g.size.height)
                    })
            }
            .frame(height: min(choicesHeight, 260))
            .onPreferenceChange(ChoicesHeightKey.self) { choicesHeight = $0 }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The search box: plain words or filters (`res:4k`, `kind:video since:30d`).
struct SearchBox: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            FilterPills(model: model, drives: drives)
            TextField(model.pills.isEmpty ? L("search.prompt") : "", text: $model.text)
                .textFieldStyle(.plain)
            if !model.text.isEmpty || model.hasFilters {
                Button {
                    model.text = ""
                    model.clearFilters()
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help(L("filters.clear"))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

/// The middle: the files as a list, thumbnails, contact sheet or timeline.
struct FilesArea: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        Group {
            if model.results.isEmpty, case let .drive(name) = model.place, let wait = drives.waiting(named: name) {
                // A chosen drive that is not ready yet: say what it waits for.
                VStack(spacing: 8) {
                    Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text(name).font(.headline)
                    Text(wait).foregroundStyle(.secondary)
                    Text(L("drive.waiting.help")).font(.caption).foregroundStyle(.secondary)
                }
            } else if model.results.isEmpty && !model.searching {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.problem ?? L("results.none")).foregroundStyle(.secondary)
                    if model.hasFilters {
                        Button(L("filters.clear")) { model.clearFilters() }
                    }
                }
            } else {
                switch model.viewMode {
                case .list: ResultsList(model: model)
                case .grid: ResultsGrid(model: model)
                case .sheet: ContactSheet(model: model)
                case .timeline: TimelineView(model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onKeyPress(.space) {
            model.quickLook()
            return .handled
        }
        .onDeleteCommand { model.trash(model.selectedHits, undo: undo) }
    }
}

/// The bottom margin: about the selected file — its name, kind, size, date
/// and details, and its full path (selectable, to copy); several selected:
/// how many and how big; none: how many files, Select All. Work in progress
/// (indexing, a notice) on the right.
struct BottomBar: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            let hits = model.selectedHits
            if hits.count == 1, let h = hits.first {
                FileIcon(path: h.path, size: 26, thumbnail: h.kind == "image" || h.kind == "video")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(h.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        Text(([kindText(h.kind), h.isDir ? "" : bytesText(h.size), dateText(h.modified)] + h.badges)
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(friendlyPath(h.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(h.path)
                }
                .layoutPriority(1)
            } else if hits.count > 1 {
                Image(systemName: "square.stack").font(.title3).foregroundStyle(.secondary)
                Text(String(format: L("results.selected"), hits.count, bytesText(hits.reduce(0) { $0 + $1.size })))
                    .fontWeight(.semibold)
                Text(countText(Int(model.total), "item")).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(countText(Int(model.total), "item")).monospacedDigit()
                if !model.canLoadMore, !model.results.isEmpty {
                    Text(bytesText(model.results.reduce(0) { $0 + $1.size })).foregroundStyle(.secondary).monospacedDigit()
                }
                if case let .drive(name) = model.place, let d = drives.drives.first(where: { $0.name == name }), d.totalBytes > 0 {
                    Text(String(format: L("drive.free"), bytesText(d.freeBytes))).foregroundStyle(.secondary)
                }
                if model.total > 0 {
                    Button(String(format: L("results.selectAll"), model.total)) { model.selectAll() }.buttonStyle(.link)
                }
            }
            if model.canLoadMore {
                Button(L("results.more")) { model.loadMore() }.buttonStyle(.link)
            }
            Spacer(minLength: 8)
            if let n = model.notice {
                Text(n).foregroundStyle(.secondary).lineLimit(1)
            }
            if let p = model.status?.indexing {
                ProgressView().controlSize(.small)
                Text(String(format: L("status.indexing"), (p.root as NSString).lastPathComponent))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 46)
    }
}

struct ChoicesHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
