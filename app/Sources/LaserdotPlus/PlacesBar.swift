import LaserdotKit
import SwiftUI

/// Places, as a band over the files (the owner: "better placed over the main
/// window, similar to Laserdot original"): everything plugged in, this Mac,
/// and each drive with its state. Click to look there; right-click a drive
/// to eject, index (a read-only one) or unlock it.
struct PlacesBar: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Capsule().fill(ChoiceBands.color("where")).frame(width: 4)
            Image(systemName: "externaldrive")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ChoiceBands.color("where"))
                .frame(width: 14, height: 18)
                .accessibilityHidden(true)
            FlowLayout(spacing: 4, lineSpacing: 5) {
                Text(L("sidebar.places")).font(.caption2.weight(.medium)).foregroundStyle(.secondary).fixedSize()
                place(.everywhere, L("place.everywhere"), "square.stack.3d.up", nil)
                place(.thisMac, L("place.thisMac"), "laptopcomputer", nil)
                ForEach(drives.drives, id: \.mount) { d in drive(d) }
            }
            .padding(.vertical, 3)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChoiceBands.color("where").opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    @ViewBuilder private func place(_ p: Place, _ title: String, _ symbol: String, _ detail: String?) -> some View {
        let on = model.place == p
        let button = Button { model.place = p } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                if let detail { Text(detail).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary) }
            }
            .font(.caption)
        }
        .controlSize(.small)
        .fixedSize()
        if on { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    @ViewBuilder private func drive(_ d: Drive) -> some View {
        let p = Place.drive(d.name)
        let on = model.place == p
        let label = HStack(spacing: 4) {
            Image(systemName: drives.isWaiting(d) ? "hourglass" : d.readOnly ? "lock" : "externaldrive")
            Text(d.name)
            Text(drives.stateText(d)).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
        }
        .font(.caption)
        let button = Button {
            switch d.state {
            case "locked": drives.unlock(d)
            case "detached":
                model.place = p // shown at once, with the hourglass, while it opens
                drives.attach(d)
            case "opening":
                model.place = p // the engine is opening it already
            case "unindexed" where d.readOnly: drives.index(d)
            default: model.place = p
            }
        } label: { label }
        .controlSize(.small)
        .fixedSize()
        .help(d.totalBytes > 0 ? String(format: L("drive.space"), bytesText(d.freeBytes), bytesText(d.totalBytes)) : d.name)
        .contextMenu {
            Button(L("drive.eject")) { drives.eject(d) }
            if d.state == "unindexed" { Button(L("drive.index")) { drives.index(d) } }
            if d.state == "locked" { Button(L("drive.unlock")) { drives.unlock(d) } }
        }
        if on { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}
