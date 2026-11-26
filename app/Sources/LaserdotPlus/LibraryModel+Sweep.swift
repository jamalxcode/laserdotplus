import AppKit
import LaserdotKit

/// Review mode's steps and What Is This?: the unclear names, their suggested
/// names, and renaming (one file, or all after a preview; always undoable).
extension LibraryModel {
    /// "What is this?": review mode over the listed files whose names say
    /// nothing (IMG_1234, VID_2034, untitled…), with a suggested name each.
    func startSweep() {
        let unclear = results.filter { !$0.isDir && NameSense.isUnclear($0.name) }
        guard let first = unclear.first else {
            notice = L("sweep.none")
            return
        }
        sweep = unclear
        reviewIndex = 0
        selectOne(first.path)
    }

    func reviewStep(_ delta: Int) {
        guard let i = reviewIndex else { return }
        let items = reviewItems
        let next = i + delta
        if sweep == nil, next >= items.count, canLoadMore { loadMore() }
        guard !items.isEmpty else { reviewIndex = nil; return }
        reviewIndex = max(0, min(items.count - 1, next))
        if let r = reviewIndex { selectOne(items[r].path) }
    }

    /// The name suggested for a file, from its details (once they are read).
    func suggestedName(_ h: Hit) -> String? {
        guard let d = details, d.path == h.path else { return nil }
        return Self.suggestion(h, d)
    }

    static func suggestion(_ h: Hit, _ d: FileDetails) -> String? {
        var rows: [String: String] = [:]
        for s in d.sections { for r in s.rows where rows[r.key] == nil { rows[r.key] = r.value } }
        let name = NameSense.suggest(name: h.name, modified: h.modified, kind: h.kind, rows: rows)
        return name == h.name ? nil : name
    }

    /// Rename a file in its folder (Edit ▸ Undo puts the old name back); in
    /// the sweep, it then leaves the list and the next one shows.
    /// What Is This? ▸ Rename All: every unclear name to its suggestion,
    /// after a preview; one Undo puts every name back.
    func renameAllSuggestions(undo: UndoManager?) {
        guard let items = sweep, !items.isEmpty else { return }
        let engine = self.engine
        notice = L("sweep.renameAll.reading")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var plan: [(Hit, String)] = []
            for h in items {
                if let d = try? engine.details(path: h.path), let s = Self.suggestion(h, d) { plan.append((h, s)) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.notice = nil
                guard !plan.isEmpty else { self.notice = L("sweep.renameAll.none"); return }
                let alert = NSAlert()
                alert.messageText = String(format: L("sweep.renameAll.confirm"), plan.count)
                alert.informativeText = plan.prefix(8).map { "\($0.0.name)  →  \($0.1)" }.joined(separator: "\n")
                    + (plan.count > 8 ? "\n…" : "")
                alert.addButton(withTitle: L("sweep.renameAll"))
                alert.addButton(withTitle: L("action.cancel"))
                guard alert.runFront() == .alertFirstButtonReturn else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                var done: [(from: URL, to: URL)] = []
                for (h, name) in plan {
                    let from = URL(fileURLWithPath: h.path)
                    let dir = from.deletingLastPathComponent()
                    var to = dir.appendingPathComponent(name)
                    let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
                    var n = 2
                    while FileManager.default.fileExists(atPath: to.path) {
                        to = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
                        n += 1
                    }
                    if (try? FileManager.default.moveItem(at: from, to: to)) != nil { done.append((from, to)) }
                }
                DispatchQueue.main.async {
                undo?.registerUndo(withTarget: self) { m in
                    for d in done.reversed() { try? FileManager.default.moveItem(at: d.to, to: d.from) }
                    m.tellEngine(done.flatMap { [$0.from, $0.to] })
                    m.schedule(now: true, keepSelection: true)
                }
                undo?.setActionName(L("sweep.renameAll"))
                self.notice = String(format: L("sweep.renameAll.done"), done.count)
                self.tellEngine(done.flatMap { [$0.from, $0.to] })
                self.sweep = nil
                self.reviewIndex = nil
                self.schedule(now: true, keepSelection: true)
                }
                }
            }
        }
    }

    func rename(_ h: Hit, to newName: String, undo: UndoManager?) {
        let from = URL(fileURLWithPath: h.path)
        var to = from.deletingLastPathComponent().appendingPathComponent(newName)
        var n = 2
        let stem = (newName as NSString).deletingPathExtension, ext = (newName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: to.path) {
            to = from.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            trouble = error.localizedDescription
            return
        }
        undo?.registerUndo(withTarget: self) { m in
            try? FileManager.default.moveItem(at: to, to: from)
            m.tellEngine([from, to])
            m.schedule(now: true, keepSelection: true)
        }
        undo?.setActionName(L("sweep.rename"))
        notice = String(format: L("notice.renamed"), to.lastPathComponent)
        tellEngine([from, to])
        if var s = sweep, let i = reviewIndex {
            s.removeAll { $0.path == h.path }
            sweep = s
            if s.isEmpty { reviewIndex = nil } else { reviewIndex = min(i, s.count - 1); selectOne(s[reviewIndex!].path) }
        }
        schedule(now: true, keepSelection: true)
    }
}
