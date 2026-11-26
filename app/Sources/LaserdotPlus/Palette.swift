import SwiftUI
import UniformTypeIdentifiers

/// Colours that colour-blind eyes tell apart (Okabe–Ito), with an icon
/// beside each so colour is never the only cue (the owner: "a color blind
/// friendly color" for the places, and the kinds under them).
enum Palette {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    /// Places (everything plugged in, this Mac, each drive): Okabe–Ito blue.
    static let place = rgb(0, 114, 178)

    /// One colour per kind of file.
    static func kind(_ k: String) -> Color {
        switch k {
        case "video": return rgb(213, 94, 0) // vermillion
        case "image": return rgb(0, 158, 115) // bluish green
        case "audio": return rgb(204, 121, 167) // reddish purple
        case "document": return rgb(86, 180, 233) // sky blue
        case "folder": return rgb(230, 159, 0) // orange
        case "archive": return rgb(240, 228, 66) // yellow
        default: return .gray // code, app, other
        }
    }

    static func kindIcon(_ k: String) -> String {
        switch k {
        case "video": return "film"
        case "image": return "photo"
        case "audio": return "music.note"
        case "document": return "doc.text"
        case "folder": return "folder"
        case "archive": return "archivebox"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "app": return "app"
        default: return "doc"
        }
    }

    /// The kind an extension's files are ("mp4" → video), as macOS knows it.
    static func kind(ofExtension ext: String) -> String {
        guard let t = UTType(filenameExtension: ext.lowercased()) else { return "other" }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return "video" }
        if t.conforms(to: .image) { return "image" }
        if t.conforms(to: .audio) { return "audio" }
        if t.conforms(to: .archive) { return "archive" }
        if t.conforms(to: .sourceCode) || t.conforms(to: .script) { return "code" }
        if t.conforms(to: .application) || t.conforms(to: .applicationBundle) { return "app" }
        if t.conforms(to: .text) || t.conforms(to: .pdf) || t.conforms(to: .presentation)
            || t.conforms(to: .spreadsheet) || t.conforms(to: .rtf) || t.conforms(to: .commaSeparatedText) { return "document" }
        return "other"
    }

    /// The kind a choice stands for: `kind:video` → video, `ext:txt` →
    /// document; nil for any other choice.
    static func kind(ofToken token: String) -> String? {
        let t = token.hasPrefix("-") ? String(token.dropFirst()) : token
        if t.hasPrefix("kind:") { return String(t.dropFirst(5)) }
        if t.hasPrefix("ext:") { return kind(ofExtension: String(t.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) }
        return nil
    }
}

/// A choice chip tinted with its kind's colour: a light fill and a border of
/// that colour, the label in the normal text colour (readable on any tint).
struct TintedChipStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(configuration.isPressed ? 0.40 : 0.20)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.75), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}
