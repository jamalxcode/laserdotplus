import Foundation

/// Names that say nothing, and better ones (the owner: "the idea is to
/// quickly scan through media … where the filename might not be enough to
/// tell what it is"). Plain rules on the name and the file's details — no AI.
public enum NameSense {
    private static let unclear: NSRegularExpression = {
        let camera = "(img|dsc|dscn|dscf|dcim|pxl|vid|mov|mvi|gopr|gp|gh|dji|cimg|sam|wp|pict|imag|photo|image|video|clip|file|scan|document|doc|recording|audio|untitled|new|copy|screenshot|screen shot|screen recording|capture)"
        // A camera/app prefix with a number, a bare number or date stamp, a
        // long hex or id string, or "untitled"-like words alone.
        let pattern = "^(" + camera + "[ _\\-]?\\(?\\d*\\)?([ _\\-].*)?" + "|[\\d _\\-.]{4,}" + "|[0-9a-f\\-]{16,}" + "|p\\d{6,}" + ")$"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// A bare number, date stamp or long hex id: says nothing on its own.
    private static let bare = try! NSRegularExpression(pattern: "^([\\d _\\-.]{4,}|[0-9a-f\\-]{16,}|p\\d{6,})$", options: [.caseInsensitive])

    /// Whether a file's name says nothing about what it is ("IMG_1234.jpg",
    /// "VID_20240812_183011.mp4", "untitled 3.pdf", "8f14e45fceea167a.mov").
    public static func isUnclear(_ name: String) -> Bool {
        let stem = ((name as NSString).deletingPathExtension).trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty else { return true }
        let r = NSRange(stem.startIndex..., in: stem)
        if let m = bare.firstMatch(in: stem, range: r), m.range == r { return true }
        guard let m = unclear.firstMatch(in: stem, range: r), m.range == r else { return false }
        // "IMG_1234 Rome beach" has words of its own: it says something.
        let words = stem.lowercased().split(whereSeparator: { " _-.()".contains($0) })
            .map { String($0.filter { !$0.isNumber }) }
            .filter { !$0.isEmpty && !camWords.contains($0) }
        return words.isEmpty
    }

    private static let camWords: Set<String> = [
        "img", "dsc", "dscn", "dscf", "dcim", "pxl", "vid", "mov", "mvi", "gopr", "gp", "gh", "dji", "cimg", "sam", "wp",
        "pict", "imag", "photo", "image", "video", "clip", "file", "scan", "document", "doc", "recording", "audio",
        "untitled", "new", "copy", "screenshot", "screen", "shot", "capture", "at", "pm", "am", "edited", "final", "of",
    ]

    /// A name built from what the file holds: its date (when the photo was
    /// taken, else when the file changed), its title or the camera, the
    /// video's resolution and length. "2023-08-14 iPhone 12 Pro 1080p 0m42s.mp4".
    public static func suggest(name: String, modified: Int64, kind: String, rows: [String: String]) -> String {
        var parts: [String] = []
        if let taken = rows["photo.taken"], taken.count >= 10 {
            parts.append(String(taken.prefix(10)))
        } else if modified > 0 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            parts.append(f.string(from: Date(timeIntervalSince1970: TimeInterval(modified))))
        }
        if let title = rows["tags.title"], !title.isEmpty {
            parts.append(title)
        } else if let cam = rows["photo.camera"], !cam.isEmpty {
            parts.append(cam)
        } else if let artist = rows["tags.artist"], !artist.isEmpty {
            parts.append(artist)
        }
        if kind == "video", let res = rows["video.resolution"], let h = res.split(separator: "×").last.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            parts.append(h >= 2000 ? "4K" : h >= 1000 ? "1080p" : h >= 700 ? "720p" : "SD")
        }
        if let d = rows["general.duration"], let secs = seconds(d), secs > 0, kind == "video" || kind == "audio" {
            parts.append(secs >= 3600 ? "\(secs / 3600)h\(secs % 3600 / 60)m" : "\(secs / 60)m\(secs % 60)s")
        }
        var stem = parts.joined(separator: " ")
        stem = stem.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if stem.isEmpty { return name }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? stem : stem + "." + ext
    }

    /// "1:02:03" or "0:42" → seconds.
    static func seconds(_ clock: String) -> Int? {
        let n = clock.split(separator: ":").compactMap { Int($0) }
        guard !n.isEmpty, n.count <= 3 else { return nil }
        return n.reduce(0) { $0 * 60 + $1 }
    }
}
