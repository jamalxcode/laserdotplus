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
            }
            .width(min: 180, ideal: 320)
            TableColumn(L("column.kind"), value: \Hit.kind) { h in Text(kindText(h.kind)).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 80)
            TableColumn(L("column.size"), value: \Hit.size) { h in
                Text(h.isDir ? "" : bytesText(h.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn(L("column.modified"), value: \Hit.modified) { h in Text(dateText(h.modified)).foregroundStyle(.secondary) }
                .width(min: 100, ideal: 150)
            TableColumn(L("column.details")) { h in Text(h.badges.joined(separator: " · ")).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 80, ideal: 200)
            TableColumn(L("column.where")) { h in Text(whereText(h.path)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                .width(min: 80, ideal: 200)
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

    var body: some View {
        let n = hits.count
        Button(n > 1 ? String(format: L("action.openMany"), n) : L("action.open")) { model.open(hits) }
        Button(L("action.quickLook")) { model.quickLook(hits) }
        Button(n > 1 ? String(format: L("action.revealMany"), n) : L("action.reveal")) { model.reveal(hits) }
        Button(n > 1 ? String(format: L("action.copyMany"), n) : L("action.copy")) { model.copyPaths(hits) }
        Divider()
        Button(L("tray.markTrash")) { model.mark(hits, .trash) }
        Button(L("tray.markMove")) { model.mark(hits, .move) }
        if hits.contains(where: { model.tray[$0.path] != nil }) {
            Button(L("tray.unmark")) { model.unmark(hits.map(\.path)) }
        }
        Divider()
        Button(n > 1 ? String(format: L("action.trashMany"), n) : L("action.trash")) { model.trash(hits, undo: undo) }
    }
}
