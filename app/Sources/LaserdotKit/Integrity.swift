import Foundation

/// A picture, video or song that cannot be what it claims (Clean Up ▸ Broken).
public struct BrokenItem: Decodable, Hashable, Sendable {
    public var path: String
    public var size: UInt64
    /// empty, unreadable, no_picture, no_length.
    public var why: String
    public var volume: String?
}

/// A drive's checksum list (bit-rot protection), kept on the drive.
public struct ChecksumStatus: Decodable, Sendable {
    public var exists: Bool
    public var files: UInt64
    public var savedAt: Int64
    /// Files on the drive not in the list yet.
    public var unlisted: UInt64

    enum CodingKeys: String, CodingKey { case exists, files, savedAt = "saved_at", unlisted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exists = (try? c.decode(Bool.self, forKey: .exists)) ?? false
        files = (try? c.decode(UInt64.self, forKey: .files)) ?? 0
        savedAt = (try? c.decode(Int64.self, forKey: .savedAt)) ?? 0
        unlisted = (try? c.decode(UInt64.self, forKey: .unlisted)) ?? 0
    }
}

public struct ChecksumReport: Decodable, Sendable {
    public var files: UInt64
    public var read: UInt64
    public var damaged: [String]
    public var missing: [String]
    public var changed: UInt64
    public var stopped: Bool

    enum CodingKeys: String, CodingKey { case files, read, damaged, missing, changed, stopped }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = (try? c.decode(UInt64.self, forKey: .files)) ?? 0
        read = (try? c.decode(UInt64.self, forKey: .read)) ?? 0
        damaged = (try? c.decode([String].self, forKey: .damaged)) ?? []
        missing = (try? c.decode([String].self, forKey: .missing)) ?? []
        changed = (try? c.decode(UInt64.self, forKey: .changed)) ?? 0
        stopped = (try? c.decode(Bool.self, forKey: .stopped)) ?? false
    }
}

public struct ChecksumProgress: Decodable, Sendable {
    public var running: Bool
    public var phase: String
    public var done: UInt64
    public var total: UInt64
    public var bytes: UInt64
    public var current: String

    enum CodingKeys: String, CodingKey { case running, phase, done, total, bytes, current }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decode(Bool.self, forKey: .running)) ?? false
        phase = (try? c.decode(String.self, forKey: .phase)) ?? ""
        done = (try? c.decode(UInt64.self, forKey: .done)) ?? 0
        total = (try? c.decode(UInt64.self, forKey: .total)) ?? 0
        bytes = (try? c.decode(UInt64.self, forKey: .bytes)) ?? 0
        current = (try? c.decode(String.self, forKey: .current)) ?? ""
    }
}

extension Engine {
    /// Broken media in a scope (a search; "" everything), from the index.
    public func broken(scope: String) throws -> [BrokenItem] {
        (try longCall(longJobConnection(), .broken(query: scope), as: [BrokenItem]?.self)) ?? []
    }

    public func checksumStatus(mount: String) throws -> ChecksumStatus {
        try longCall(longJobConnection(), .checksumStatus(mount: mount), as: ChecksumStatus.self)
    }

    /// Read the drive's new or changed files and keep their checksums on it
    /// (long: every file is read once; it can be stopped and continued).
    public func saveChecksums(mount: String) throws -> ChecksumReport {
        try longCall(longJobConnection(), .checksumSave(mount: mount), as: ChecksumReport.self)
    }

    /// Read the listed files again: damage, missing, changed.
    public func checkChecksums(mount: String) throws -> ChecksumReport {
        try longCall(longJobConnection(), .checksumCheck(mount: mount), as: ChecksumReport.self)
    }

    public func checksumProgress() -> ChecksumProgress? {
        try? longCall(longJobConnection(), .checksumProgress, as: ChecksumProgress.self)
    }

    public func stopChecksums() {
        _ = try? longCall(longJobConnection(), .checksumStop, as: Bool.self)
    }
}
