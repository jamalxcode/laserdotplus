import LaserdotKit
import SwiftUI

/// Laserdot's compact choices, under the toolbar: each family (what, file,
/// picture, time, photo, music, document) is a band of its own colour and
/// icon, its groups' values as chips with counts, wrapping onto a few rows.
/// A click narrows to a value (several in a group: any of them); ⌥-click
/// leaves it out. Chosen values move into the search box as pills. The calm
/// view shows each group's biggest values and the first bands; More choices
/// shows the rest.
struct ChoiceBands: View {
    @ObservedObject var model: LibraryModel
    /// Groups whose quiet values (no results now) are unfolded.
    @State private var revealed: Set<String> = []

    static func isLive(_ o: RefineOption) -> Bool { o.count > 0 || o.isWaitingDrive }
    static func hasLive(_ g: RefineGroup) -> Bool { g.options.contains(where: isLive) }

    var body: some View {
        let open = model.openGroups
        let calm = RefineLogic.compact(RefineLogic.arranged(open), expanded: model.allChoices)
        if !open.isEmpty {
            // The top area scrolls (it can be made smaller or bigger).
            Group {
                let all = RefineLogic.bands(calm.shown)
                let liveBands = all.filter { $0.groups.contains(where: Self.hasLive) }
                let quietBands = all.filter { !$0.groups.contains(where: Self.hasLive) }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(liveBands, id: \.family) { band in
                        HStack(alignment: .top, spacing: 6) {
                            Capsule().fill(Self.color(band.family)).frame(width: 4)
                            Image(systemName: Self.icon(band.family))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Self.color(band.family))
                                .frame(width: 14, height: 18)
                                .accessibilityHidden(true)
                            FlowLayout(spacing: 4, lineSpacing: 5) {
                                ForEach(Array(band.groups.enumerated()), id: \.element.id) { gi, g in
                                    Text(Self.groupTitle(g.id))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, gi == 0 ? 0 : 12)
                                        .fixedSize()
                                    // What can be chosen, then the rest folded into
                                    // a small "+N" (click to see them).
                                    let live = g.options.filter(Self.isLive)
                                    let quiet = g.options.filter { !Self.isLive($0) }
                                    ForEach(live, id: \.token) { o in
                                        chip(o, in: g).fixedSize()
                                    }
                                    if revealed.contains(g.id) {
                                        ForEach(quiet, id: \.token) { o in
                                            chip(o, in: g).fixedSize()
                                        }
                                    }
                                    if !quiet.isEmpty {
                                        Button(revealed.contains(g.id) ? "−" : "+\(quiet.count)") {
                                            if revealed.contains(g.id) { revealed.remove(g.id) } else { revealed.insert(g.id) }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .help(String(format: L("choices.quiet"), quiet.count))
                                        .fixedSize()
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Self.color(band.family).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if !quietBands.isEmpty {
                        // Bands with nothing to choose now: one short line.
                        Text(String(format: L("choices.nothingIn"),
                                    quietBands.flatMap(\.groups).map { Self.groupTitle($0.id) }.joined(separator: " · ")))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .padding(.leading, 6)
                    }
                    if calm.hidden > 0 || model.allChoices {
                        Button(model.allChoices ? L("choices.fewer") : String(format: L("choices.more"), calm.hidden)) {
                            model.allChoices.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .padding(.leading, 6)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private func chip(_ o: RefineOption, in g: RefineGroup) -> some View {
        let label = Self.label(o)
        if o.count == 0 && !o.isWaitingDrive {
            // Nothing to choose here now: small and quiet, it grows back into
            // a chip as soon as it gives results.
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
                .help(String(format: L("choices.none"), label))
        } else {
            liveChip(o, label: label, in: g)
        }
    }

    private func liveChip(_ o: RefineOption, label: String, in g: RefineGroup) -> some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                model.exclude(g.id, o.token, label: label)
            } else {
                model.toggle(g.id, o.token, label: label)
            }
        } label: {
            Text("\(label) ").font(.caption) + Text(o.count > 0 ? "\(o.count)" : "").font(.caption).foregroundColor(.secondary)
        }
        .help(String(format: L("choices.help"), label))
        .contextMenu {
            Button(L("choices.leaveOut")) { model.exclude(g.id, o.token, label: label) }
        }
    }

    static func groupTitle(_ id: String) -> String {
        let s = L("refine.group." + id)
        return s == "refine.group." + id ? id.capitalized : s
    }

    static func label(_ o: RefineOption) -> String {
        if let k = o.key {
            let s = L("refine." + k)
            if s != "refine." + k { return s }
        }
        return o.label
    }

    /// Okabe–Ito colours (distinct for colour-blind eyes), one per family.
    static func color(_ family: String) -> Color {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        switch family {
        case "where": return rgb(0, 114, 178)
        case "what": return rgb(230, 159, 0)
        case "file": return rgb(86, 180, 233)
        case "picture": return rgb(0, 158, 115)
        case "time": return rgb(213, 94, 0)
        case "photo": return rgb(204, 121, 167)
        case "music": return rgb(181, 160, 0)
        case "doc": return .primary
        default: return .gray
        }
    }

    static func icon(_ family: String) -> String {
        switch family {
        case "where": return "externaldrive"
        case "what": return "square.grid.2x2"
        case "file": return "doc"
        case "picture": return "photo"
        case "time": return "clock"
        case "photo": return "camera"
        case "music": return "music.note"
        case "doc": return "doc.text.magnifyingglass"
        default: return "line.3.horizontal.decrease"
        }
    }
}

/// The chosen values, as pills in the search box (✕ takes one out; a left-
/// out one reads "not …").
struct FilterPills: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(model.pills, id: \.token) { p in
                HStack(spacing: 2) {
                    let wait = p.isPlace ? drives.waiting(named: p.label) : nil
                    if p.isPlace {
                        Image(systemName: wait != nil ? "hourglass" : p.label == L("place.thisMac") ? "desktopcomputer" : "externaldrive")
                    }
                    Text(p.excluded ? String(format: L("choices.not"), p.label) : p.label)
                        .strikethrough(p.excluded)
                        .lineLimit(1)
                    if let wait {
                        Text(wait).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Button { model.removePill(p) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help(L("choices.remove"))
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(p.excluded ? 0.10 : 0.20)))
                .fixedSize()
            }
        }
    }
}
