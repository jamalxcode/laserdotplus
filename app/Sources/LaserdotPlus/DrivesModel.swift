import AppKit
import LaserdotKit

/// The drives plugged in. A writable drive is indexed by itself as soon as
/// it is connected (its index stays on the drive); a read-only one only when
/// asked (its index then lives on this Mac until the drive leaves, and is
/// deleted then). Unplugged drives disappear: nothing about them is kept.
final class DrivesModel: ObservableObject {
    @Published private(set) var drives: [Drive] = []
    /// What is being done to a drive now ("Ejecting plex media…").
    @Published private(set) var busy: [String: String] = [:]
    var onChange: () -> Void = {}

    private let engine: Engine
    private var timer: Timer?
    private var listing = false
    /// Drives indexed by themselves this session (each once).
    private var started = Set<String>()

    init(engine: Engine) {
        self.engine = engine
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// The drive list has not come back for a while: a drive is not
    /// answering (asleep, a bad cable…). Said in the bottom bar.
    @Published private(set) var notAnswering = false
    private var listingSince = Date()

    func refresh() {
        if listing {
            if Date().timeIntervalSince(listingSince) > 12, !notAnswering { notAnswering = true }
            return
        }
        listing = true
        listingSince = Date()
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = (try? engine.drives()) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.listing = false
                if self.notAnswering { self.notAnswering = false }
                let changed = list.map { "\($0.mount)|\($0.state)|\($0.entries / 1000)" } != self.drives.map { "\($0.mount)|\($0.state)|\($0.entries / 1000)" }
                self.drives = list
                list.forEach(DriveHistory.noteSnapshot) // once a day, on the drive
                if changed { self.onChange() }
                self.indexNewDrives()
            }
        }
    }

    /// A writable drive with no index starts indexing on its own (not a disk
    /// image opened to install an app).
    private func indexNewDrives() {
        for d in drives where d.state == "unindexed" && !d.readOnly && !started.contains(d.mount) && busy[d.mount] == nil {
            started.insert(d.mount)
            let mount = d.mount
            let engine = self.engine
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if InstallerVolume.isInstaller(mount: mount, readOnly: false) { return }
                _ = try? engine.driveIndex(mount: mount, passphrase: nil)
                DispatchQueue.main.async { self?.refresh() }
            }
        }
    }

    /// Index a drive now (a read-only one, or one indexing stopped).
    func index(_ d: Drive) {
        started.insert(d.mount)
        run(d, L("drive.busy.indexing")) { engine in _ = try engine.driveIndex(mount: d.mount, passphrase: nil) }
    }

    func eject(_ d: Drive) {
        run(d, L("drive.busy.ejecting")) { engine in try engine.driveEject(mount: d.mount) }
    }

    func unlock(_ d: Drive) {
        let alert = NSAlert()
        alert.messageText = String(format: L("drive.unlock.title"), d.name)
        alert.informativeText = L("drive.unlock.help")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L("drive.unlock"))
        alert.addButton(withTitle: L("action.cancel"))
        guard alert.runFront() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        let secret = field.stringValue
        run(d, L("drive.busy.unlocking")) { engine in try engine.driveUnlock(mount: d.mount, passphrase: secret) }
    }

    func attach(_ d: Drive) {
        run(d, L("drive.busy.attaching")) { engine in try engine.driveAttach(mount: d.mount) }
    }

    private func run(_ d: Drive, _ what: String, _ work: @escaping (Engine) throws -> Void) {
        busy[d.mount] = what
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Result { try work(engine) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy[d.mount] = nil
                if case let .failure(e) = outcome {
                    let alert = NSAlert()
                    alert.messageText = d.name
                    alert.informativeText = (e as? LaserdotError)?.message ?? e.localizedDescription
                    alert.runFront()
                }
                self.refresh()
            }
        }
    }

    /// Not ready yet: being opened, indexed for the first time, or busy. Its
    /// place still shows (the owner: "it should still appear but with an
    /// indicator like an hourglass saying there is some waiting involved").
    func isWaiting(_ d: Drive) -> Bool {
        busy[d.mount] != nil || (d.state == "detached" && (d.detail ?? "").isEmpty) || d.state == "opening" || (d.state == "unindexed" && !d.readOnly)
            || (d.state == "attached" && d.indexing)
    }

    /// What a chosen drive is waiting for ("Opening its index…"), or nil when
    /// it is ready.
    func waiting(named name: String) -> String? {
        guard let d = drives.first(where: { $0.name == name }), isWaiting(d) else { return nil }
        return stateText(d)
    }

    /// Everything about a drive, for its card (About This Drive).
    /// About This Drive: a window with its facts, its history and its
    /// protection against bit rot.
    @Published var info: DriveSheet?
    func showInfo(_ d: Drive) { info = DriveSheet(id: d.mount, drive: d) }

    /// One line under the drive's name.
    /// When each drive started opening (not published: it only changes the
    /// text, which the drive list's own refresh redraws).
    private var openingSince: [String: Date] = [:]

    func stateText(_ d: Drive) -> String {
        if let b = busy[d.mount] { return b }
        if d.state == "opening" || (d.state == "detached" && (d.detail ?? "").isEmpty) {
            // How long it has been opening, so a slow one does not look stuck.
            let since = openingSince[d.mount] ?? Date()
            openingSince[d.mount] = since
            let s = Int(Date().timeIntervalSince(since))
            if s >= 3 { return String(format: L("drive.busy.attachingFor"), durationText(Double(s))) }
        } else {
            openingSince[d.mount] = nil
        }
        switch d.state {
        case "attached":
            return d.indexing ? String(format: L("drive.state.indexing"), d.entries) : String(format: L("drive.state.ready"), d.entries)
        case "locked": return L("drive.state.locked")
        case "detached" where !(d.detail ?? "").isEmpty: return L("drive.state.cannotOpen") // why: in the tooltip
        case "detached", "opening": return L("drive.busy.attaching") // the engine opens it by itself
        case "unreadable": return L("drive.state.unreadable")
        default: return d.readOnly ? L("drive.state.readOnly") : L("drive.state.waiting")
        }
    }
}
