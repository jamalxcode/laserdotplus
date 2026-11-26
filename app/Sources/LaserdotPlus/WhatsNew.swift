import AppKit
import LaserdotKit

/// What's New after an update (the critique: with frequent releases, a short
/// note says what to try) and Help ▸ Keyboard Shortcuts. The notes are the
/// CHANGELOG bundled in the app; nothing is fetched.
enum WhatsNew {
    static let seenKey = "whatsNew.lastSeen"

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    static var changelog: String {
        Bundle.main.url(forResource: "CHANGELOG", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// At launch: once per new version (not on the very first launch).
    static func showIfUpdated() {
        let d = UserDefaults.standard
        let seen = d.string(forKey: seenKey)
        d.set(version, forKey: seenKey)
        guard let seen, Changelog.newer(version, than: seen) else { return }
        show(after: seen)
    }

    static func show(after: String?) {
        let secs = Changelog.sections(changelog, after: after, upTo: version)
        guard !secs.isEmpty else { return }
        let text = secs.map { "\($0.version)\n\n\($0.text)" }.joined(separator: "\n\n")
        present(title: String(format: L("whatsNew.title"), version), body: text)
    }

    static func showShortcuts() {
        present(title: L("shortcuts.title"), body: L("shortcuts.body"))
    }

    private static func present(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        scroll.hasVerticalScroller = true
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.drawsBackground = false
        tv.autoresizingMask = [.width]
        let md = (try? NSAttributedString(markdown: body.replacingOccurrences(of: "\n", with: "  \n"),
                                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        tv.textStorage?.setAttributedString(md ?? NSAttributedString(string: body))
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .labelColor
        scroll.documentView = tv
        alert.accessoryView = scroll
        alert.addButton(withTitle: L("action.done"))
        alert.runFront()
    }
}
