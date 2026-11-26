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
