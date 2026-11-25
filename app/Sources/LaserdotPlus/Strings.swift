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
    appResources.localizedString(forKey: key, value: key, table: nil)
}

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
    let dir = (path as NSString).deletingLastPathComponent
    var parts = dir.split(separator: "/").map(String.init)
    let home = NSHomeDirectory().split(separator: "/").map(String.init)
    if parts.starts(with: home) {
        parts = ["~"] + parts.dropFirst(home.count)
    } else if parts.first == "Volumes", parts.count > 1 {
        parts = Array(parts.dropFirst())
    }
    if parts.count > 4 { parts = [parts[0], "…"] + parts.suffix(2) }
    return parts.joined(separator: " › ")
}

/// A file kind in words ("Video").
func kindText(_ kind: String) -> String {
    let s = L("kind." + kind)
    return s == "kind." + kind ? kind.capitalized : s
}

extension Hit: Identifiable {
    public var id: String { path }
}
