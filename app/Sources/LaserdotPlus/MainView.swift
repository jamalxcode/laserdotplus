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

    /// The inspector shows unless Review or Clean Up takes the window.
    private var inspector: Binding<Bool> {
        Binding(get: { model.showInspector && model.reviewIndex == nil && !model.showDupes },
                set: { model.showInspector = $0 })
    }

    var body: some View {
        // Finder's layout (the owner chose it): the places in a sidebar, the
        // files in the middle, the file's preview and details in an inspector,
        // the controls in the window's toolbar.
        NavigationSplitView {
            Sidebar(model: model, drives: drives, views: model.views)
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                // The top hugs what it shows (no empty band above the files).
                TopArea(model: model, drives: drives)
                Divider()
                FilesArea(model: model, drives: drives)
                    .frame(minWidth: 420, minHeight: 240)
                    // Review and Clean Up take the whole middle.
                    .overlay {
                        if model.reviewIndex != nil {
                            ReviewView(model: model)
                        } else if model.showDupes {
                            CleanupView(model: model, drives: drives, junk: model.junk, big: model.bigOld)
                        }
                    }
                if !model.tray.isEmpty {
                    Divider()
                    TrayBar(model: model)
                }
                Divider()
                BottomBar(model: model, drives: drives)
            }
            .inspector(isPresented: inspector) {
                DetailsView(model: model)
                    .inspectorColumnWidth(min: 200, ideal: 260, max: 460)
            }
            .toolbar { MainToolbar(model: model) }
        }
        .navigationTitle("Laserdot+")
        .navigationSubtitle(subtitle)
    }

    /// Where you are and how much is there, under the title (as in Finder).
    private var subtitle: String {
        "\(model.placeTitle) — \(countText(Int(model.total), "file"))"
    }
}

/// The window's toolbar: how the files are shown, their order, the tools, and
/// the inspector.
struct MainToolbar: ToolbarContent {
    @ObservedObject var model: LibraryModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker(L("menu.view"), selection: $model.viewMode) {
                Label(L("view.list"), systemImage: "list.bullet").tag(ViewMode.list)
                Label(L("view.grid"), systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label(L("view.sheet"), systemImage: "film.stack").tag(ViewMode.sheet)
                Label(L("view.timeline"), systemImage: "calendar").tag(ViewMode.timeline)
            }
            .pickerStyle(.segmented)
            .help(L("menu.view"))
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
                Label(L("sort.by"), systemImage: "arrow.up.arrow.down")
            }
            .help(L("sort.by"))
            Menu {
                Button { model.startSweep() } label: { Label(L("sweep.menu"), systemImage: "questionmark.square.dashed") }
                    .disabled(model.results.isEmpty)
                Button { model.startReview() } label: { Label(L("review.start"), systemImage: "rectangle.stack.badge.play") }
                    .disabled(model.results.isEmpty)
                Divider()
                Button { model.openCleanup(.duplicates) } label: { Label(L("dupes.menu"), systemImage: "square.on.square") }
                Button { model.openCleanup(.junk) } label: { Label(L("cleanup.junk.menu"), systemImage: "trash.slash") }
                Button { model.openCleanup(.bigOld) } label: { Label(L("cleanup.bigOld.menu"), systemImage: "externaldrive.badge.timemachine") }
                Button { model.openCleanup(.space) } label: { Label(L("space.menu"), systemImage: "chart.bar.xaxis") }
            } label: {
                Label(L("tools.title"), systemImage: "wand.and.stars")
            }
            .help(L("tools.help"))
            Button { model.showInspector.toggle() } label: { Label(L("inspector.toggle"), systemImage: "sidebar.right") }
                .help(L("inspector.toggle"))
        }
    }
}

/// The top: the search box, then the choice bands (scrolling when the area is
/// made small). The places are in the sidebar, the controls in the toolbar.
struct TopArea: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel
    /// The choices' natural height: the area is that tall (up to a cap,
    /// then it scrolls), never taller.
    @State private var choicesHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            SearchBox(model: model, drives: drives)
                .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            FilterPills(model: model, drives: drives)
            TextField(model.pills.isEmpty ? L("search.prompt") : "", text: $model.text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onChange(of: model.focusSearch) { _, _ in focused = true }
            if !model.text.isEmpty || model.hasFilters {
                Button {
                    model.text = ""
                    model.clearFilters()
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help(L("filters.clear"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        // A darker, bolder frame draws the eye to it (the owner); the places'
        // blue while typing in it.
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? Palette.place : Color.primary.opacity(0.55), lineWidth: focused ? 2.5 : 2))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
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
                ContentUnavailableView {
                    Label(name, systemImage: "hourglass")
                } description: {
                    Text(wait + "\n" + L("drive.waiting.help"))
                }
            } else if model.results.isEmpty && !model.searching {
                ContentUnavailableView {
                    Label(model.problem ?? L("results.none"), systemImage: "magnifyingglass")
                } actions: {
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
        // A folder dropped on the window (from Finder) is indexed.
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { u in
                var dir: ObjCBool = false
                return u.isFileURL && FileManager.default.fileExists(atPath: u.path, isDirectory: &dir) && dir.boolValue
            }
            folders.forEach { model.index(folder: $0.path) }
            return !folders.isEmpty
        }
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
                        let opened = model.details.flatMap { $0.path == h.path ? $0 : nil }?
                            .sections.first { $0.id == "dates" }?.rows.first { $0.key == "dates.opened" }?.value
                        Text(([kindText(h.kind), h.isDir ? "" : bytesText(h.size),
                               String(format: L("bar.modified"), dateText(h.modified)),
                               h.created > 0 ? String(format: L("bar.created"), dateText(h.created)) : "",
                               opened.map { String(format: L("bar.opened"), $0) } ?? ""] + h.badges)
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
            if let t = model.trouble {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(t).lineLimit(2).textSelection(.enabled)
                    Button { model.trouble = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("trouble.dismiss"))
                }
            } else if let n = model.notice {
                Text(n).foregroundStyle(.secondary).lineLimit(1)
            }
            if let text = model.indexingText {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(.secondary).lineLimit(1)
            }
            if drives.notAnswering {
                Label(L("drive.notAnswering"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).lineLimit(1)
                    .help(L("drive.notAnswering.help"))
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
