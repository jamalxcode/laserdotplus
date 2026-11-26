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
            FlowLayout(spacing: 4, lineSpacing: 5) {
                place(.everywhere, L("place.everywhere"), "square.stack.3d.up", nil)
                place(.thisMac, L("place.thisMac"), "laptopcomputer", nil)
                ForEach(drives.drives, id: \.mount) { d in drive(d) }
            }
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func place(_ p: Place, _ title: String, _ symbol: String, _ detail: String?) -> some View {
        let on = model.place == p
        let button = Button { model.place = p } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                if let detail { Text(detail).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary) }
            }
            .font(.callout)
        }
        .controlSize(.regular)
        .fixedSize()
        if on { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    @ViewBuilder private func drive(_ d: Drive) -> some View {
        let p = Place.drive(d.name)
        let on = model.place == p
        let label = HStack(spacing: 5) {
            Image(systemName: drives.isWaiting(d) ? "hourglass" : d.state == "locked" ? "lock.fill"
                  : !(d.detail ?? "").isEmpty ? "exclamationmark.triangle" : d.readOnly ? "lock" : "externaldrive")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(d.name).fontWeight(.medium)
                    Text(drives.stateText(d)).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
                }
                // How full it is, at a glance.
                if d.totalBytes > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill((on ? Color.white : Color.secondary).opacity(0.25))
                            Capsule().fill(on ? Color.white : Color.accentColor)
                                .frame(width: g.size.width * CGFloat(Double(d.totalBytes - min(d.freeBytes, d.totalBytes)) / Double(d.totalBytes)))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .font(.callout)
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
        .help(!(d.detail ?? "").isEmpty ? (d.detail ?? "")
              : d.totalBytes > 0 ? String(format: L("drive.space"), bytesText(d.freeBytes), bytesText(d.totalBytes)) : d.name)
        .contextMenu {
            Button(L("drive.eject")) { drives.eject(d) }
            if d.state == "unindexed" { Button(L("drive.index")) { drives.index(d) } }
            if d.state == "locked" { Button(L("drive.unlock")) { drives.unlock(d) } }
        }
        if on { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}
