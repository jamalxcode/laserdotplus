import Foundation
import LaserdotKit

/// A drive's own history (the owner chose it): how full it was over time, and
/// what clean-ups freed. Kept on the drive (`.laserdot/history.json`), never
/// on this Mac, and only on a drive that already holds its index there.
struct DriveHistoryEntry: Codable, Hashable {
    var t: Int64
    var used: UInt64?
    var total: UInt64?
    var files: UInt64?
    /// A clean-up: bytes put in the Trash.
    var freed: UInt64?
}

enum DriveHistory {
    private static let io = DispatchQueue(label: "laserdotplus.history", qos: .utility)
    /// Snapshots taken this session (at most one a day per drive).
    private static var noted: [String: String] = [:]
    private static let lock = NSLock()

    static func file(_ mount: String) -> URL {
        URL(fileURLWithPath: mount).appendingPathComponent(".laserdot").appendingPathComponent("history.json")
    }

    /// Read on the caller's thread (call it off the main thread).
    static func load(_ mount: String) -> [DriveHistoryEntry] {
        (try? Data(contentsOf: file(mount))).flatMap { try? JSONDecoder().decode([DriveHistoryEntry].self, from: $0) } ?? []
    }

    private static func append(_ mount: String, _ e: DriveHistoryEntry) {
        io.async {
            let dir = file(mount).deletingLastPathComponent()
            var isDir: ObjCBool = false
            // Only where the drive keeps its own index: nothing is created
            // on a drive whose index is on this Mac (read-only, encrypted).
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return }
            var all = load(mount)
            all.append(e)
            if all.count > 3000 { all.removeFirst(all.count - 3000) }
            if let data = try? JSONEncoder().encode(all) { try? data.write(to: file(mount), options: .atomic) }
        }
    }

    /// How full the drive is today (once a day).
    static func noteSnapshot(_ d: Drive) {
        guard d.state == "attached", d.onDrive, !d.encrypted, !d.readOnly, d.totalBytes > 0 else { return }
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        lock.lock()
        let seen = noted[d.mount] == day
        noted[d.mount] = day
        lock.unlock()
        guard !seen else { return }
        let mount = d.mount
        let entry = DriveHistoryEntry(t: Int64(Date().timeIntervalSince1970), used: d.totalBytes - min(d.freeBytes, d.totalBytes),
                                      total: d.totalBytes, files: d.entries)
        io.async {
            // Already noted today on an earlier launch?
            if let last = load(mount).last(where: { $0.used != nil }),
               ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(last.t)), timeZone: .current,
                                           formatOptions: [.withFullDate]) == day { return }
            append(mount, entry)
        }
    }

    /// Files just put in the Trash (their new places): what each drive freed.
    static func noteCleanup(trashed: [URL]) {
        io.async {
            var byMount: [String: UInt64] = [:]
            for u in trashed {
                let parts = u.path.split(separator: "/")
                guard parts.count > 2, parts[0] == "Volumes" else { continue }
                let size = (try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))
                    .flatMap { $0.totalFileAllocatedSize ?? $0.fileSize } ?? 0
                byMount["/Volumes/" + parts[1], default: 0] += UInt64(size)
            }
            for (mount, bytes) in byMount where bytes > 0 {
                append(mount, DriveHistoryEntry(t: Int64(Date().timeIntervalSince1970), freed: bytes))
            }
        }
    }

    /// Months until full, from how fast it filled over the last six months
    /// (nil: not enough history, or not filling).
    static func monthsUntilFull(_ entries: [DriveHistoryEntry]) -> Double? {
        let now = Date().timeIntervalSince1970
        let points = entries.filter { $0.used != nil && Double($0.t) > now - 183 * 86400 }
        guard let first = points.first, let last = points.last, let total = last.total,
              let u0 = first.used, let u1 = last.used else { return nil }
        let days = Double(last.t - first.t) / 86400
        guard days >= 7, u1 > u0 else { return nil }
        let perDay = Double(u1 - u0) / days
        return Double(total - min(u1, total)) / perDay / 30.4
    }
}
