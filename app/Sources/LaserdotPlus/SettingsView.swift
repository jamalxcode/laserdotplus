import SwiftUI

/// Laserdot+ ▸ Settings… (⌘,): the choices that were spread over menus and
/// panels, in one place, as every Mac app has. Only how the app works is kept
/// here — nothing about any file or drive.
struct SettingsView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var updates = Updates.shared

    var body: some View {
        TabView {
            Form {
                Toggle(L("updates.daily"), isOn: $updates.daily)
                Toggle(L("inspector.show"), isOn: $model.showInspector)
            }
            .tabItem { Label(L("settings.general"), systemImage: "gearshape") }
            DupesSettings(dupes: model.dupes)
                .tabItem { Label(L("dupes.menu"), systemImage: "square.on.square") }
            BigOldSettings(big: model.bigOld)
                .tabItem { Label(L("cleanup.bigOld.menu"), systemImage: "externaldrive.badge.timemachine") }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
    }
}

private struct DupesSettings: View {
    @ObservedObject var dupes: DupesModel

    var body: some View {
        Form {
            Picker(L("dupes.larger"), selection: $dupes.minMB) {
                ForEach(DupesModel.sizes, id: \.self) { mb in
                    Text(mb == 0 ? L("dupes.anySize") : mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                }
            }
            Toggle(L("dupes.similar"), isOn: $dupes.similar)
        }
    }
}

private struct BigOldSettings: View {
    @ObservedObject var big: BigOldModel

    var body: some View {
        Form {
            Picker(L("dupes.larger"), selection: $big.minMB) {
                ForEach(BigOldModel.sizes, id: \.self) { mb in Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb) }
            }
            Picker(L("settings.oldBy"), selection: $big.byOpened) {
                Text(L("cleanup.notChanged")).tag(false)
                Text(L("cleanup.notOpened")).tag(true)
            }
            Picker(L("cleanup.for"), selection: $big.years) {
                ForEach(BigOldModel.ages, id: \.self) { y in Text(String(format: L("cleanup.years"), y)).tag(y) }
            }
        }
    }
}
