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
