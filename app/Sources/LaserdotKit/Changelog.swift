import Foundation

/// The CHANGELOG's "## x.y.z" sections (What's New after an update).
public enum Changelog {
    /// The sections of versions after `after` (nil: all), up to and including
    /// `upTo`, newest first as written.
    public static func sections(_ changelog: String, after: String?, upTo: String) -> [(version: String, text: String)] {
        var out: [(String, String)] = []
        var current: String?
        var lines: [String] = []
        func flush() {
            if let v = current, newer(v, than: after), !newer(v, than: upTo) {
                out.append((v, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            lines = []
        }
        for line in changelog.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                current = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if current != nil {
                lines.append(line)
            }
        }
        flush()
        return out
    }

    /// Whether version a is newer than b (nil: always), number by number.
    public static func newer(_ a: String, than b: String?) -> Bool {
        guard let b else { return true }
        let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
