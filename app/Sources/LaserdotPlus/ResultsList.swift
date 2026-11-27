import AppKit
import LaserdotKit
import SwiftUI

/// Finder's list: name, what it is, size, date, details, where. Click a
/// column to sort (the engine sorts the whole collection, not just the rows
/// on screen); ⌘/⇧-click and dragging select several.
struct ResultsList: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo
    @State private var order: [KeyPathComparator<Hit>] = []

    var body: some View {
        Table(model.results, selection: $model.selection, sortOrder: $order) {
            TableColumn(L("column.name"), value: \Hit.name) { h in
                HStack(spacing: 6) {
                    FileIcon(path: h.path, size: 18, thumbnail: h.kind == "image" || h.kind == "video")
                    Text(h.name).lineLimit(1).truncationMode(.middle)
                }
                .onAppear { model.reached(h) }
            }
            .width(min: 120, ideal: 260)
            TableColumn(L("column.size"), value: \Hit.size) { h in
                Text(h.isDir ? "" : bytesText(h.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 80)
            TableColumn(L("column.modified"), value: \Hit.modified) { h in Text(dateText(h.modified)).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 80, ideal: 160)
            TableColumn(L("column.created"), value: \Hit.created) { h in
                Text(h.created > 0 ? dateText(h.created) : "").foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 70, ideal: 150)
            TableColumn(L("column.opened"), value: \Hit.opened) { h in
                Text(h.opened > 0 ? dateText(h.opened) : "—").foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 70, ideal: 150)
            TableColumn(L("column.details")) { h in Text(h.badges.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 50, ideal: 200)
            TableColumn(L("column.where")) { h in Text(whereText(h.path)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                .width(min: 50, ideal: 200)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            FileMenu(model: model, hits: model.results.filter { ids.contains($0.path) }, undo: undo)
        } primaryAction: { ids in
            model.open(model.results.filter { ids.contains($0.path) })
        }
        .onChange(of: order) { _, new in
            guard let first = new.first else { return }
            let path = first.keyPath
            let key: SortKey
            if path == \Hit.name as PartialKeyPath<Hit> {
                key = .name
            } else if path == \Hit.size as PartialKeyPath<Hit> {
                key = .size
            } else if path == \Hit.kind as PartialKeyPath<Hit> {
                key = .kind
            } else if path == \Hit.created as PartialKeyPath<Hit> {
                key = .created
            } else if path == \Hit.opened as PartialKeyPath<Hit> {
                model.sortByOpened(reverse: first.order == .reverse)
                return
            } else {
                key = .modified
            }
            model.sort = key
            model.reverse = first.order == .reverse
        }
    }
}

/// The right-click menu, for one file or the whole selection (as in Finder).
struct FileMenu: View {
    @ObservedObject var model: LibraryModel
    let hits: [Hit]
    let undo: UndoManager?

    /// In Finder's order: open, Trash, info and name, look, copy and show.
    var body: some View {
        let n = hits.count
        Button(n > 1 ? String(format: L("action.openMany"), n) : L("action.open")) { model.open(hits) }
        if let first = hits.first {
            OpenWithMenu(model: model, hits: hits, url: URL(fileURLWithPath: first.path))
        }
        Divider()
        Button(n > 1 ? String(format: L("action.trashMany"), n) : L("action.trash")) { model.trash(hits, undo: undo) }
        Divider()
        Button(L("action.getInfo")) { model.getInfo(hits) }
        if n == 1, let h = hits.first {
            Button(L("action.rename")) { model.renamePrompt(h, undo: undo) }
        }
        Button(L("action.quickLook")) { model.quickLook(hits) }
        Divider()
        Button(n > 1 ? String(format: L("action.copyMany"), n) : L("action.copy")) { model.copyPaths(hits) }
        Button(n > 1 ? String(format: L("action.revealMany"), n) : L("action.reveal")) { model.reveal(hits) }
        Divider()
        Button(L("tray.markTrash")) { model.mark(hits, .trash) }
        Button(L("tray.markMove")) { model.mark(hits, .move) }
        if hits.contains(where: { model.tray[$0.path] != nil }) {
            Button(L("tray.unmark")) { model.unmark(hits.map(\.path)) }
        }
    }
}

/// Open With ▸ the apps that can open the file (the default first), as in
/// Finder. Files open without being added to Recent Items.
struct OpenWithMenu: View {
    @ObservedObject var model: LibraryModel
    let hits: [Hit]
    let url: URL

    var body: some View {
        Menu(L("action.openWith")) {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            let main = NSWorkspace.shared.urlForApplication(toOpen: url)
            ForEach(Array(apps.prefix(20)), id: \.self) { app in
                Button {
                    model.open(hits, with: app)
                } label: {
                    Text(FileManager.default.displayName(atPath: app.path) + (app == main ? " " + L("action.openWith.default") : ""))
                }
            }
        }
    }
}
