import Foundation

// Laserdot+: the details panel's content, read from the file's header on
// request (the engine's `details` op); nothing is stored.

public struct DetailRow: Decodable, Hashable, Sendable {
    public var key: String
    public var value: String
}

public struct DetailSection: Decodable, Hashable, Sendable {
    public var id: String
    public var rows: [DetailRow]
}

public struct FileDetails: Decodable, Sendable {
    public var path: String
    public var name: String
    public var kind: String
    public var isDir: Bool
    public var size: UInt64
    public var modified: Int64
    public var sections: [DetailSection]

    enum CodingKeys: String, CodingKey {
        case path, name, kind, size, modified, sections
        case isDir = "is_dir"
    }

    /// Tolerant: missing or null fields read as empty (a picture with no
    /// camera details came as `"sections": null` and the whole answer was
    /// lost — no details, no suggested name).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? (path as NSString).lastPathComponent
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        isDir = try c.decodeIfPresent(Bool.self, forKey: .isDir) ?? false
        size = try c.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        modified = try c.decodeIfPresent(Int64.self, forKey: .modified) ?? 0
        sections = try c.decodeIfPresent([DetailSection].self, forKey: .sections) ?? []
    }
}

extension Engine {
    /// Everything known about one file. On a connection of its own: reading
    /// a sleeping drive's header must hold up neither searches nor the drive
    /// list.
    public func details(path: String) throws -> FileDetails {
        detailsLock.lock()
        defer { detailsLock.unlock() }
        if detailsClient == nil, let c = DaemonClient.connectLive(socketPath: socketPath) {
            c.setTimeout(30)
            detailsClient = c
        }
        guard let c = detailsClient else { return try call(.details(path: path), as: FileDetails.self) }
        do {
            return try c.call(.details(path: path), as: FileDetails.self)
        } catch DaemonClientError.remote(let e) {
            throw LaserdotError(e)
        } catch {
            detailsClient = nil
            throw LaserdotError.unavailable("\(error)")
        }
    }
}

/// A file or folder nobody needs (Laserdot+'s clean-up screen).
public struct JunkItem: Decodable, Hashable, Sendable {
    public var path: String
    public var size: UInt64
    /// system, partial, empty_file, empty_folder.
    public var why: String
}

extension Engine {
    /// The junk under a folder ("" every place): a walk of the disk, on a
    /// connection of its own, no time limit.
    public func junk(path: String) throws -> [JunkItem] {
        (try longCall(longJobConnection(), .junk(path: path), as: [JunkItem]?.self)) ?? []
    }

    /// The running junk walk: found so far, folders gone through, the one it
    /// is in (nil: an older engine, or no answer). On a connection of its own.
    /// Only the finds from the from'th on (a big drive has tens of thousands).
    public func junkFound(from: Int) -> JunkProgress? {
        try? longCall(longJobConnection(), .junkFound(from: from), as: JunkProgress.self)
    }

    /// End the running junk walk early (it returns what it found).
    public func stopJunk() {
        _ = try? longCall(longJobConnection(), .junkStop, as: Bool.self)
    }
}

/// A junk walk while it runs.
public struct JunkProgress: Decodable, Sendable {
    public var running: Bool
    public var folders: UInt64
    public var current: String
    public var items: [JunkItem]
    /// `items` start at this find; `total` finds so far.
    public var from: Int
    public var total: Int

    enum CodingKeys: String, CodingKey { case running, folders, current, items, from, total }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decode(Bool.self, forKey: .running)) ?? false
        folders = (try? c.decode(UInt64.self, forKey: .folders)) ?? 0
        current = (try? c.decode(String.self, forKey: .current)) ?? ""
        items = (try? c.decode([JunkItem].self, forKey: .items)) ?? []
        from = (try? c.decode(Int.self, forKey: .from)) ?? 0
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
    }
}

/// One file's dates (Unix seconds; 0: not recorded).
public struct FileTime: Decodable, Hashable, Sendable {
    public var path: String
    public var created: Int64
    public var modified: Int64
    public var opened: Int64
    public var added: Int64
}

extension Engine {
    /// The dates of these files (last opened as macOS records it), read from
    /// the files, on a connection of its own; by the page.
    public func fileTimes(_ paths: [String]) -> [FileTime] {
        guard !paths.isEmpty else { return [] }
        var out: [FileTime] = []
        let line = longJobConnection()
        for start in stride(from: 0, to: paths.count, by: 2000) {
            let batch = Array(paths[start..<min(paths.count, start + 2000)])
            out += (try? longCall(line, .fileTimes(paths: batch), as: [FileTime]?.self)) ?? []
        }
        return out
    }
}
