import Foundation
import LaserdotKit

/// The app's resources (strings in English and Arabic). In Laserdot+.app
/// they live in Contents/Resources, the only place code signing allows;
/// SwiftPM's generated `Bundle.module` looks beside the .app instead and
/// would stop the app, so it is only the fallback (swift run, tests).
let appResources: Bundle = {
    let name = "LaserdotPlus_LaserdotPlus.bundle"
    let places = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
    for case let dir? in places {
        if let b = Bundle(url: dir.appendingPathComponent(name)) { return b }
    }
    return Bundle.module
}()

/// The app's words in the user's language (English or Arabic).
func L(_ key: String) -> String {
    let s = appResources.localizedString(forKey: key, value: key, table: nil)
    // English first (the owner): a string not yet in another language shows
    // in English, never as its key.
    if s == key, let en = englishResources { return en.localizedString(forKey: key, value: key, table: nil) }
    return s
}

private let englishResources: Bundle? = appResources.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))

/// The language the app's strings use ("en" or "ar").
let appLang: String = appResources.preferredLocalizations.first ?? "en"

/// "4.2 GB"
func bytesText(_ n: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .file)
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.doesRelativeDateFormatting = true
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

/// "Today, 14:02" from Unix seconds.
func dateText(_ unix: Int64) -> String {
    unix <= 0 ? "" : dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
}

/// "plex media › Films › 2019": where a file is, short.
func whereText(_ path: String) -> String {
    var parts = placeParts((path as NSString).deletingLastPathComponent)
    if parts.count > 4 { parts = [parts[0], "…"] + parts.suffix(2) }
    return parts.joined(separator: " › ")
}

/// A path as Finder would say it: "T5 EVO › Movies › 2023 › clip.mp4",
/// "Home › Pictures › …" — the whole of it, no system folders.
func friendlyPath(_ path: String) -> String { placeParts(path).joined(separator: " › ") }

/// The parts of a path, from its drive or Home (macOS's own /private and
/// temporary folders left out).
func placeParts(_ path: String) -> [String] {
    var parts = path.split(separator: "/").map(String.init)
    let home = NSHomeDirectory().split(separator: "/").map(String.init)
    if parts.starts(with: home) {
        parts = [L("path.home")] + parts.dropFirst(home.count)
    } else if parts.first == "Volumes", parts.count > 1 {
        parts = Array(parts.dropFirst())
    } else if parts.starts(with: ["private", "var", "folders"]) || parts.starts(with: ["var", "folders"]) {
        parts = Array(parts.suffix(3)) // a temporary folder: only the end means anything
    } else {
        if parts.first == "private" { parts.removeFirst() }
        parts = [L("place.thisMac")] + parts
    }
    return parts
}

/// "1 file", "12 files" (and the like in Arabic).
func countText(_ n: Int, _ unit: String) -> String {
    String(format: L("unit." + unit + (n == 1 ? ".one" : ".many")), n)
}

/// A file kind in words ("Video").
func kindText(_ kind: String) -> String {
    let s = L("kind." + kind)
    return s == "kind." + kind ? kind.capitalized : s
}

extension Hit: Identifiable {
    public var id: String { path }
}

/// "3 min", "1 h 20 min", "40 s".
func durationText(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s) s" }
    if s < 3600 { return "\(s / 60) min" }
    return "\(s / 3600) h \(s % 3600 / 60) min"
}
