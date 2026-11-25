import LaserdotKit
import SwiftUI

/// Places (everything, this Mac, each drive plugged in) and the filters:
/// every choice the current files have, with counts. Several ticks in one
/// group show files with any of them; groups narrow each other.
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
            Section {
                if model.groups.isEmpty {
                    Text(L("filters.none")).foregroundStyle(.secondary).font(.callout)
                }
                ForEach(model.groups, id: \.id) { g in
                    FilterGroupView(model: model, group: g)
                }
            } header: {
                HStack {
                    Text(L("sidebar.filters"))
                    Spacer()
                    if model.hasFilters {
                        Button(L("filters.clear")) { model.clearFilters() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
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

/// One group of choices ("Resolution": 4K 12 · 1080p 40 …), open by default.
struct FilterGroupView: View {
    @ObservedObject var model: LibraryModel
    let group: RefineGroup
    @State private var open = true

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            ForEach(group.options, id: \.token) { o in
                Toggle(isOn: Binding(get: { model.isOn(group.id, o.token) }, set: { _ in model.toggle(group.id, o.token) })) {
                    HStack {
                        Text(label(o)).lineLimit(1)
                        Spacer()
                        if o.count > 0 {
                            Text("\(o.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(o.count == 0 && !model.isOn(group.id, o.token))
            }
        } label: {
            Text(groupTitle).font(.callout.weight(.semibold))
        }
    }

    private var groupTitle: String {
        let s = L("refine.group." + group.id)
        return s == "refine.group." + group.id ? group.id.capitalized : s
    }

    private func label(_ o: RefineOption) -> String {
        if let k = o.key {
            let s = L("refine." + k)
            if s != "refine." + k { return s }
        }
        return o.label
    }
}
