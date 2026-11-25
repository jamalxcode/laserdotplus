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
                }
                .pickerStyle(.segmented)
                .help(L("menu.view"))
                if model.viewMode == .grid {
                    Slider(value: $model.tileSize, in: 96...320)
                        .frame(width: 110)
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
                SearchBox(text: $model.text)
                    .frame(width: 280)
            }
        }
        .navigationTitle("Laserdot+")
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
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("search.prompt"), text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
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
            Group {
                if model.results.isEmpty && !model.searching {
                    emptyState
                } else if model.viewMode == .list {
                    ResultsList(model: model)
                } else {
                    ResultsGrid(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
