import AppKit
import SwiftUI

/// Saved views (the critique: "4K videos over 10 GB" should come back when
/// that drive is plugged in). A drive's views are kept on the drive
/// (`.laserdot/views.json`), never on this Mac; This Mac's and Everything's
/// beside this Mac's index. Read and written off the main thread.
struct SavedView: Codable, Hashable {
    var name: String
    var text: String
    var filters: [String: [String]]
    var excluded: [String]
    var labels: [String: String]
}

final class SavedViews: ObservableObject {
    @Published private(set) var views: [SavedView] = []
    private(set) var file: URL?
    private let io = DispatchQueue(label: "laserdotplus.views", qos: .utility)

    /// `mount`: the drive's own mount (a second drive of the same name is at
    /// "/Volumes/<name> 1"); "/Volumes/<name>" when not known.
    static func file(for place: Place, mount: String? = nil, dbPath: String) -> URL {
        if case let .drive(name) = place {
            return URL(fileURLWithPath: mount ?? Place.mount(of: name))
                .appendingPathComponent(".laserdot").appendingPathComponent("views.json")
        }
        return URL(fileURLWithPath: dbPath).deletingLastPathComponent().appendingPathComponent("views.json")
    }

    func load(_ url: URL) {
        file = url
        io.async { [weak self] in
            let v = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([SavedView].self, from: $0) } ?? []
            DispatchQueue.main.async {
                guard let self, self.file == url else { return }
                self.views = v
            }
        }
    }

    func save(_ v: SavedView) {
        views.removeAll { $0.name == v.name }
        views.append(v)
        write()
    }

    func rename(_ name: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name else { return }
        views.removeAll { $0.name == n } // a view of that name is replaced
        guard let i = views.firstIndex(where: { $0.name == name }) else { return }
        views[i].name = n
        write()
    }

    /// Move a view one place left (-1) or right (+1).
    func move(_ name: String, by delta: Int) {
        guard let i = views.firstIndex(where: { $0.name == name }) else { return }
        let j = i + delta
        guard views.indices.contains(j) else { return }
        views.swapAt(i, j)
        write()
    }

    func remove(_ name: String) {
        views.removeAll { $0.name == name }
        write()
    }

    static func askName(_ title: String, current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.addButton(withTitle: L("views.rename"))
        alert.addButton(withTitle: L("action.cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runFront() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func write() {
        guard let url = file else { return }
        let data = try? JSONEncoder().encode(views)
        io.async {
            guard let data else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic) // a read-only drive keeps none
        }
    }
}

extension LibraryModel {
    /// The search as it is now, to save under a name.
    func currentView(named name: String) -> SavedView {
        SavedView(name: name, text: text, filters: filtersForSaving, excluded: excludedForSaving, labels: labelsForSaving)
    }

    /// Ask a name and save the current search as a view of this place.
    func saveViewPrompt() {
        // Privacy: a view kept on this Mac must not name a drive's folders.
        if case .drive = place {} else {
            let v = currentView(named: "")
            let tokens = v.filters.values.flatMap { $0 } + v.excluded + [v.text]
            if tokens.contains(where: { $0.contains("/Volumes/") || $0.hasPrefix("volume:") && $0 != "volume:local" }) {
                notice = L("views.save.pickDrive")
                return
            }
        }
        let alert = NSAlert()
        alert.messageText = L("views.save.title")
        alert.informativeText = String(format: L("views.save.where"), placeTitle)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = L("views.save.placeholder")
        alert.accessoryView = field
        alert.addButton(withTitle: L("views.save"))
        alert.addButton(withTitle: L("action.cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runFront() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        views.save(currentView(named: name))
    }
}
