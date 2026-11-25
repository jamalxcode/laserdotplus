import LaserdotKit
import SwiftUI

/// The window: places and filters on the left, the files in the middle,
/// everything about the selected file on the right.
struct MainView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        // A plain three-pane layout (not NavigationSplitView: its sidebar is
        // drawn in a way window captures — the self-test's screenshots —
        // cannot see).
        HSplitView {
            SidebarView(model: model, drives: drives)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 380)
            ResultsView(model: model)
                .frame(minWidth: 420, idealWidth: 700, maxWidth: .infinity)
            DetailsView(model: model)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text(title).font(.headline).lineLimit(1)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(L("menu.view"), selection: $model.viewMode) {
                    Label(L("view.list"), systemImage: "list.bullet").tag(ViewMode.list)
                    Label(L("view.grid"), systemImage: "square.grid.2x2").tag(ViewMode.grid)
                    Label(L("view.sheet"), systemImage: "film.stack").tag(ViewMode.sheet)
                    Label(L("view.timeline"), systemImage: "calendar").tag(ViewMode.timeline)
                }
                .pickerStyle(.segmented)
                .help(L("menu.view"))
                Button { model.startReview() } label: { Label(L("review.start"), systemImage: "rectangle.stack.badge.play") }
                    .help(L("review.start"))
                    .disabled(model.results.isEmpty)
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
                SearchBox(model: model)
                    .frame(minWidth: 200, idealWidth: 320, maxWidth: 420)
            }
        }
        .navigationTitle("Laserdot+")
        .overlay {
            if model.reviewIndex != nil {
                ReviewView(model: model)
            }
        }
    }

    private var title: String {
        switch model.place {
        case .everywhere: return L("place.everywhere")
        case .thisMac: return L("place.thisMac")
        case let .drive(name): return name
        }
    }
}

/// The search box: plain words or filters (`res:4k`, `kind:video since:30d`).
struct SearchBox: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            FilterPills(model: model)
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

/// The middle: the files as a list or a grid, a status line under them.
struct ResultsView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        VStack(spacing: 0) {
            ChoiceBands(model: model)
            Group {
                if model.results.isEmpty && !model.searching {
                    emptyState
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
            if !model.tray.isEmpty {
                Divider()
                TrayBar(model: model)
            }
            Divider()
            statusLine
        }
        .onKeyPress(.space) {
            model.quickLook()
            return .handled
        }
        .onDeleteCommand { model.trash(model.selectedHits, undo: undo) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(model.problem ?? L("results.none")).foregroundStyle(.secondary)
            if model.hasFilters {
                Button(L("filters.clear")) { model.clearFilters() }
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text(String(format: L("results.count"), model.total))
                .monospacedDigit()
            if model.selection.count > 1 {
                Text(String(format: L("results.selected"), model.selection.count,
                            bytesText(model.selectedHits.reduce(0) { $0 + $1.size })))
            }
            if model.canLoadMore {
                Button(L("results.more")) { model.loadMore() }.buttonStyle(.link)
            }
            if model.total > 0 {
                Button(String(format: L("results.selectAll"), model.total)) { model.selectAll() }.buttonStyle(.link)
            }
            // One file selected: its full path (selectable, to copy).
            if model.selection.count == 1, let path = model.selection.first {
                Divider().frame(height: 12)
                Text(path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                    .layoutPriority(-1)
            }
            Spacer()
            if let n = model.notice {
                Text(n).foregroundStyle(.secondary)
            }
            if let p = model.status?.indexing {
                ProgressView().controlSize(.small)
                Text(String(format: L("status.indexing"), (p.root as NSString).lastPathComponent))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
