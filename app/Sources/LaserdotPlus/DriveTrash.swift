import AppKit
import SwiftUI

/// How much a drive's Trash holds (the critique: files moved to the Trash
/// free no space until the Trash is emptied, and a drive's Trash is easy to
/// forget). Laserdot+ never deletes: it says how much is waiting and opens
/// Finder's Trash, where it is emptied. Counted off the main thread.
final class DriveTrash: ObservableObject {
    static let shared = DriveTrash()
    @Published private(set) var bytes: [String: UInt64] = [:]
    /// The drive's free space now (with the Trash still full).
    @Published private(set) var free: [String: UInt64] = [:]
    private var counting: Set<String> = []

    /// The drive's own Trash folder (`<drive>/.Trashes/<uid>`).
    static func folder(mount: String) -> URL {
        URL(fileURLWithPath: mount).appendingPathComponent(".Trashes").appendingPathComponent(String(getuid()))
    }

    func refresh(mount: String) {
        guard !counting.contains(mount) else { return }
        counting.insert(mount)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var total: UInt64 = 0
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
            if let e = FileManager.default.enumerator(at: Self.folder(mount: mount), includingPropertiesForKeys: keys) {
                for case let url as URL in e {
                    guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                    total += UInt64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                }
            }
            let free = (try? URL(fileURLWithPath: mount).resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
                .volumeAvailableCapacity.map { UInt64(max(0, $0)) }
            DispatchQueue.main.async {
                self?.counting.remove(mount)
                self?.bytes[mount] = total
                if let free { self?.free[mount] = free }
            }
        }
    }

    /// Finder's Trash window (it shows every drive's trashed files too).
    static func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
    }
}

/// "48 GB in this drive's Trash — Open Trash", when there is something.
struct DriveTrashLine: View {
    let mount: String
    @ObservedObject var trash = DriveTrash.shared

    var body: some View {
        Group {
            if let b = trash.bytes[mount], b > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(format: L("trash.waiting"), bytesText(b)), systemImage: "trash")
                        .font(.caption)
                    if let f = trash.free[mount] {
                        // Before and after: what emptying the Trash gives back.
                        Text(String(format: L("trash.freeAfter"), bytesText(f), bytesText(f + b)))
                            .font(.caption.weight(.semibold))
                    }
                    Text(L("trash.help")).font(.caption2).foregroundStyle(.secondary)
                    Button(L("trash.open")) { DriveTrash.openTrash() }.controlSize(.small)
                }
            }
        }
        .onAppear { trash.refresh(mount: mount) }
    }
}

extension Place {
    /// Where the drive of this name is mounted (its volume name can differ
    /// from the folder in /Volumes when two drives share a name).
    static func mount(of name: String) -> String {
        let keys: [URLResourceKey] = [.volumeNameKey]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        where url.path.hasPrefix("/Volumes/") {
            if (try? url.resourceValues(forKeys: Set(keys)))?.volumeName == name || url.lastPathComponent == name { return url.path }
        }
        return "/Volumes/" + name
    }
}
