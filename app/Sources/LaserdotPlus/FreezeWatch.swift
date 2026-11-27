import AppKit

/// Notes when the window stops answering for more than 2 seconds, and which
/// step it was in (the critique: the owner had to find macOS's hang report).
/// Only fixed step names, the time and how long — never a file's name — kept
/// in this Mac's preferences, shown in Help ▸ Report a Problem….
enum FreezeWatch {
    private static let lock = NSLock()
    private static var current = "idle"
    private static var started = false
    private static var longest: (seconds: Double, step: String) = (0, "")

    /// The longest the window waited, and in which step (and start again).
    static func takeLongest() -> (seconds: Double, step: String) {
        lock.lock()
        defer { longest = (0, ""); lock.unlock() }
        return longest
    }

    /// The step the main thread is about to do ("search results", "junk finds").
    static func mark(_ step: String) {
        lock.lock()
        current = step
        lock.unlock()
    }

    private static var step: String {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    struct Entry: Codable {
        let at: Date
        let seconds: Double
        let step: String
    }

    static func start() {
        guard !started else { return }
        started = true
        let t = Thread {
            while true {
                let began = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                var during = ""
                if answered.wait(timeout: .now() + 2) == .timedOut {
                    during = step // what the stuck main thread said it was doing
                    answered.wait()
                    record(Entry(at: began, seconds: Date().timeIntervalSince(began), step: during))
                }
                if during.isEmpty { during = step }
                // The longest wait so far (the self-test fails a build that
                // makes the window stall).
                let waited = Date().timeIntervalSince(began)
                lock.lock()
                if waited > longest.seconds { longest = (waited, during) }
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        t.qualityOfService = .utility
        t.start()
    }

    private static func record(_ e: Entry) {
        var all = entries()
        all.append(e)
        if all.count > 20 { all.removeFirst(all.count - 20) }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: "freezes") }
    }

    static func entries() -> [Entry] {
        (UserDefaults.standard.data(forKey: "freezes")).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    /// The app's memory now (what Activity Monitor calls Memory).
    static func memoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Help ▸ Report a Problem…: the version, this Mac, memory and the freezes
    /// noted — nothing about any file — with Copy.
    static func showReport() {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var lines = ["Laserdot+ \(v) · macOS \(os) · memory \(bytesText(memoryBytes()))"]
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        let list = entries()
        lines.append(list.isEmpty ? L("report.noFreezes") : L("report.freezes"))
        for e in list.reversed() { lines.append("• \(f.string(from: e.at)) — \(String(format: "%.1f", e.seconds)) s — \(e.step)") }
        let text = lines.joined(separator: "\n")
        let a = NSAlert()
        a.messageText = L("report.title")
        a.informativeText = text + "\n\n" + L("report.help")
        a.addButton(withTitle: L("report.copy"))
        a.addButton(withTitle: L("action.done"))
        if a.runFront() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
