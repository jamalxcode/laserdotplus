import AppKit
import LaserdotKit
import SwiftUI

/// The sidebar, as in Finder (the owner chose it from the Mac-like review):
/// where to look — everything plugged in, this Mac, each drive with its state,
/// fullness and an eject button —, the place's saved views, and the clean-up
/// tools. Dropping files on a drive moves them there (undoable).
enum SidebarItem: Hashable {
    case everywhere, thisMac, drive(String), view(String), tool(CleanupTab)
}

struct Sidebar: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var drives: DrivesModel
    @ObservedObject var views: SavedViews
    @Environment(\.undoManager) private var undo

    private var selection: Binding<SidebarItem?> {
        Binding(get: {
            if model.showDupes { return .tool(model.cleanupTab) }
            switch model.place {
            case .everywhere: return .everywhere
            case .thisMac: return .thisMac
            case let .drive(name): return .drive(name)
            }
        }, set: { item in
            guard let item else { return }
            switch item {
            case .everywhere: model.showDupes = false; model.place = .everywhere
            case .thisMac: model.showDupes = false; model.place = .thisMac
            case let .drive(name):
                model.showDupes = false
                if let d = drives.drives.first(where: { $0.name == name }) { choose(d) } else { model.place = .drive(name) }
            case let .view(name):
                model.showDupes = false
                if let v = views.views.first(where: { $0.name == name }) { model.apply(v) }
            case let .tool(tab): model.openCleanup(tab)
            }
        })
    }

    var body: some View {
        List(selection: selection) {
            Section(L("sidebar.places")) {
                Label(L("place.everywhere"), systemImage: "square.stack.3d.up").tag(SidebarItem.everywhere)
                Label(L("place.thisMac"), systemImage: "laptopcomputer").tag(SidebarItem.thisMac)
            }
            if !drives.drives.isEmpty {
                Section(L("sidebar.drives")) {
                    ForEach(drives.drives, id: \.mount) { d in driveRow(d).tag(SidebarItem.drive(d.name)) }
                }
            }
            Section {
                ForEach(views.views, id: \.name) { v in
                    Label(v.name, systemImage: "bookmark")
                        .tag(SidebarItem.view(v.name))
                        .contextMenu { viewMenu(v) }
                }
            } header: {
                HStack {
                    Text(L("sidebar.saved"))
                    Spacer()
                    Button { model.saveViewPrompt() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help(L("views.save.help"))
                        .disabled(model.text.isEmpty && model.pills.allSatisfy(\.isPlace))
                }
            }
            Section(L("tools.title")) {
                Label(L("dupes.menu"), systemImage: "square.on.square").tag(SidebarItem.tool(.duplicates))
                Label(L("cleanup.junk.menu"), systemImage: "trash.slash").tag(SidebarItem.tool(.junk))
                Label(L("cleanup.bigOld.menu"), systemImage: "externaldrive.badge.timemachine").tag(SidebarItem.tool(.bigOld))
                Label(L("space.menu"), systemImage: "chart.bar.xaxis").tag(SidebarItem.tool(.space))
            }
        }
        .listStyle(.sidebar)
        .onAppear { reloadViews() }
        .onChange(of: model.place) { _, _ in reloadViews() }
    }

    private func reloadViews() { views.load(SavedViews.file(for: model.place, dbPath: model.engine.dbPath)) }

    /// A drive that can't be searched yet does what it needs (unlock, open,
    /// index); a ready one is chosen.
    private func choose(_ d: Drive) {
        let p = Place.drive(d.name)
        switch d.state {
        case "locked": drives.unlock(d)
        case "detached":
            model.place = p // shown at once, with the hourglass, while it opens
            drives.attach(d)
        case "unindexed" where d.readOnly: drives.index(d)
        default: model.place = p
        }
    }

    private func driveRow(_ d: Drive) -> some View {
        HStack(spacing: 6) {
            Image(systemName: drives.isWaiting(d) ? "hourglass" : d.state == "locked" ? "lock.fill"
                  : !(d.detail ?? "").isEmpty ? "exclamationmark.triangle" : d.readOnly ? "lock" : "externaldrive")
                .foregroundStyle(Palette.place)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).lineLimit(1)
                Text(drives.stateText(d)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if d.totalBytes > 0 {
                    // How full it is, at a glance.
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.25))
                            Capsule().fill(Palette.place)
                                .frame(width: g.size.width * CGFloat(Double(d.totalBytes - min(d.freeBytes, d.totalBytes)) / Double(d.totalBytes)))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 4)
            Button { drives.eject(d) } label: { Image(systemName: "eject") }
                .buttonStyle(.borderless)
                .help(L("drive.eject"))
        }
        .help(!(d.detail ?? "").isEmpty ? (d.detail ?? "")
              : d.totalBytes > 0 ? String(format: L("drive.space"), bytesText(d.freeBytes), bytesText(d.totalBytes)) : d.name)
        .contextMenu {
            Button(L("drive.about")) { drives.showInfo(d) }
            Divider()
            Button(L("drive.eject")) { drives.eject(d) }
            if d.state == "unindexed" { Button(L("drive.index")) { drives.index(d) } }
            if d.state == "locked" { Button(L("drive.unlock")) { drives.unlock(d) } }
        }
        // Files dropped on a drive move there, after a question (undoable).
        .dropDestination(for: URL.self) { urls, _ in
            let paths = urls.filter(\.isFileURL).map(\.path).filter { !$0.hasPrefix(d.mount + "/") }
            guard !paths.isEmpty else { return false }
            let a = NSAlert()
            a.messageText = String(format: L("drive.moveHere"), countText(paths.count, "file"), d.name)
            a.informativeText = L("drive.moveHere.help")
            a.addButton(withTitle: L("drive.moveHere.button"))
            a.addButton(withTitle: L("action.cancel"))
            guard a.runFront() == .alertFirstButtonReturn else { return false }
            model.movePaths(paths, to: URL(fileURLWithPath: d.mount), undo: undo)
            return true
        }
    }

    @ViewBuilder private func viewMenu(_ v: SavedView) -> some View {
        Button(L("views.rename")) {
            if let n = SavedViews.askName(L("views.rename.title"), current: v.name) { views.rename(v.name, to: n) }
        }
        Button(L("views.moveUp")) { views.move(v.name, by: -1) }.disabled(views.views.first == v)
        Button(L("views.moveDown")) { views.move(v.name, by: 1) }.disabled(views.views.last == v)
        Divider()
        Button(L("views.remove")) { views.remove(v.name) }
    }
}
