import LaserdotKit
import SwiftUI

/// Places: everything plugged in, this Mac, each drive (the filters are the
/// compact choice bands above the files, as in Laserdot).
struct SidebarView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel

    var body: some View {
        List {
            Section(L("sidebar.places")) {
                placeRow(.everywhere, L("place.everywhere"), "square.stack.3d.up", nil)
                placeRow(.thisMac, L("place.thisMac"), "laptopcomputer", nil)
                ForEach(drives.drives, id: \.mount) { d in driveRow(d) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func placeRow(_ p: Place, _ title: String, _ symbol: String, _ detail: String?) -> some View {
        Button {
            model.place = p
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(model.place == p ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(model.place == p ? .isSelected : [])
    }

    private func driveRow(_ d: Drive) -> some View {
        let chosen = model.place == .drive(d.name)
        return HStack(alignment: .top) {
            Button {
                switch d.state {
                case "locked": drives.unlock(d)
                case "detached": drives.attach(d)
                case "unindexed" where d.readOnly: drives.index(d)
                default: model.place = .drive(d.name)
                }
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: d.readOnly ? "lock.doc" : "externaldrive")
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).lineLimit(1)
                        Text(drives.stateText(d)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if d.totalBytes > 0 {
                            ProgressView(value: Double(d.totalBytes - min(d.freeBytes, d.totalBytes)), total: Double(d.totalBytes))
                                .controlSize(.mini)
                                .help(String(format: L("drive.space"), bytesText(d.freeBytes), bytesText(d.totalBytes)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                drives.eject(d)
            } label: {
                Image(systemName: "eject")
            }
            .buttonStyle(.borderless)
            .help(L("drive.eject"))
        }
        .listRowBackground(chosen ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
