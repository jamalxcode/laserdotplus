import AppKit

/// Updates (the owner: "a check for updates", then "if there is an update, i
/// want it to self update, not send me to a downloads page"): the bundled
/// laserdotplus-update-check — the only Laserdot+ code that uses the network,
/// speaking to GitHub only and sending nothing about the user or their files —
/// finds the latest release; when it is newer, Install and Relaunch has the
/// helper download it from GitHub, check it, swap it in for this copy (the old
/// one goes to the Trash) and open it. Checked when asked, and once a day
/// (on by default; the View menu turns it off).
final class Updates: ObservableObject {
    static let shared = Updates()
    @Published var daily = (UserDefaults.standard.object(forKey: "updates.daily") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(daily, forKey: "updates.daily") }
    }
    private var checking = false
    private var installing = false

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// At launch, then every hour while Laserdot+ stays open (the owner: a
    /// copy left running saw no update): once a day at most, only if on.
    private var timer: Timer?
    func startChecking() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    func checkIfDue() {
        guard daily, !SelfTest.active else { return }
        let last = UserDefaults.standard.double(forKey: "updates.last")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        check(quiet: true)
    }

    /// `quiet`: say nothing unless a newer version exists.
    func check(quiet: Bool = false) {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let found = Self.latestVersion()
            DispatchQueue.main.async {
                self.checking = false
                if found != nil { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updates.last") }
                self.show(found, quiet: quiet)
            }
        }
    }

    private func show(_ latest: String?, quiet: Bool) {
        let alert = NSAlert()
        guard let latest else {
            if quiet { return }
            alert.messageText = L("updates.failed")
            alert.informativeText = L("updates.failed.help")
            alert.runFront()
            return
        }
        if Self.newer(latest, than: current) {
            alert.messageText = String(format: L("updates.available"), latest)
            alert.informativeText = String(format: L("updates.available.help"), current)
            alert.addButton(withTitle: L("updates.install"))
            alert.addButton(withTitle: L("updates.later"))
            if alert.runFront() == .alertFirstButtonReturn {
                install(latest)
            }
        } else if !quiet {
            alert.messageText = L("updates.current")
            alert.informativeText = String(format: L("updates.current.help"), current)
            alert.runFront()
        }
    }

    /// Downloads and checks the new version off the main thread (a notice
    /// says so); once the helper says "ready", Laserdot+ quits and the helper
    /// swaps the copies and opens the new one.
    func install(_ version: String) {
        guard !installing, let exe = Bundle.main.url(forAuxiliaryExecutable: "laserdotplus-update-check") else { return }
        installing = true
        NotificationCenter.default.post(name: .updateProgress, object: String(format: L("updates.downloading"), version))
        let app = Bundle.main.bundleURL.path
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--install", version, "--app", app, "--pid", String(ProcessInfo.processInfo.processIdentifier)]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            var ready = false
            if (try? p.run()) != nil {
                // Read until "ready" (or the helper ends with a problem).
                var buffer = Data()
                while case let chunk = out.fileHandleForReading.availableData, !chunk.isEmpty {
                    buffer.append(chunk)
                    if String(decoding: buffer, as: UTF8.self).contains("ready") { ready = true; break }
                }
            }
            let problem = ready ? "" : String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                self.installing = false
                NotificationCenter.default.post(name: .updateProgress, object: nil)
                if ready {
                    NSApp.terminate(nil) // the helper takes it from here
                } else {
                    let a = NSAlert()
                    a.messageText = L("updates.installFailed")
                    a.informativeText = problem.trimmingCharacters(in: .whitespacesAndNewlines)
                    a.runFront()
                }
            }
        }
    }

    /// The bundled helper's answer ("0.1.2"), or nil.
    static func latestVersion() -> String? {
        guard let exe = Bundle.main.url(forAuxiliaryExecutable: "laserdotplus-update-check") else { return nil }
        let p = Process()
        p.executableURL = exe
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let v = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !v.isEmpty ? v : nil
    }

    /// "0.1.10" is newer than "0.1.9".
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

extension Notification.Name {
    /// The update's progress for the bottom bar (a String, or nil when done).
    static let updateProgress = Notification.Name("laserdotplus.updateProgress")
}
