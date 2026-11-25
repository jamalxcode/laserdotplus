import AppKit

/// Check for Updates… (the owner's request): runs the bundled
/// laserdotplus-update-check — the only Laserdot+ code that uses the network,
/// asking GitHub which release is the latest and sending nothing else — and,
/// when a newer version exists, offers to open its page in the browser to
/// download it. Nothing is downloaded or installed by the app itself. It
/// runs when asked, or once a day if "Check Automatically" is on (off by
/// default).
final class Updates: ObservableObject {
    static let shared = Updates()
    @Published var daily = UserDefaults.standard.bool(forKey: "updates.daily") {
        didSet { UserDefaults.standard.set(daily, forKey: "updates.daily") }
    }
    private var checking = false

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// At launch: once a day at most, only if turned on.
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
            alert.addButton(withTitle: L("updates.download"))
            alert.addButton(withTitle: L("updates.later"))
            if alert.runFront() == .alertFirstButtonReturn,
               let url = URL(string: "https://github.com/jamalxcode/laserdotplus/releases/tag/v\(latest)") {
                NSWorkspace.shared.open(url) // the browser downloads it
            }
        } else if !quiet {
            alert.messageText = L("updates.current")
            alert.informativeText = String(format: L("updates.current.help"), current)
            alert.runFront()
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
