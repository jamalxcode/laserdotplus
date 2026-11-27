import AppKit
import ImageIO
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails, made by the app itself and kept in memory only. Privacy:
/// macOS's Quick Look thumbnails would be written to a system cache on this
/// Mac, so they are not used — pictures through ImageIO, PDFs through PDFKit,
/// videos through `VideoFrames` (macOS's reader or the bundled ffmpeg).
final class Thumbs {
    static let shared = Thumbs()
    private let cache = pictureCache(megabytes: 120)
    private let icons = pictureCache(megabytes: 20)
    /// Three files read at a time, newest first (what is on screen now).
    private let gate = AsyncGate(3)
    private let iconQueue = DispatchQueue(label: "laserdotplus.icons", qos: .utility)

    /// The icon for a name's type, from the name alone (no disk read).
    private var typeIcons: [String: NSImage] = [:]

    func typeIcon(for path: String) -> NSImage {
        if let img = icons.object(forKey: path as NSString) { return img }
        let ext = (path as NSString).pathExtension.lowercased()
        // One icon per kind of file, made once (a hang report: a long list
        // asked macOS for the same type's icon row after row).
        if let img = typeIcons[ext] { return img }
        let type = ext.isEmpty ? UTType.folder : (UTType(filenameExtension: ext) ?? .data)
        let img = NSWorkspace.shared.icon(for: type)
        typeIcons[ext] = img
        return img
    }

    /// An app's or folder's own icon (custom icons), read off the main thread.
    func ownIcon(for path: String, done: @escaping (NSImage) -> Void) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext.isEmpty || ext == "app" else { return }
        if let img = icons.object(forKey: path as NSString) { return done(img) }
        iconQueue.async { [icons] in
            let img = NSWorkspace.shared.icon(forFile: path)
            cachePut(icons, img, path as NSString)
            DispatchQueue.main.async { done(img) }
        }
    }

    func thumbnail(for path: String, edge: CGFloat) async -> NSImage? {
        let key = "\(path)|\(Int(edge))" as NSString
        if let img = cache.object(forKey: key) { return img }
        if VideoFrames.isVideo(path) {
            let img = await VideoFrames.poster(path, edge: edge)
            if let img { cachePut(cache, img, key) }
            return img
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        let picture = type?.conforms(to: .image) == true
        let pdf = type?.conforms(to: .pdf) == true
        guard picture || pdf else { return nil }
        await gate.enter()
        if Task.isCancelled {
            await gate.leave()
            return nil
        }
        let img = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let url = URL(fileURLWithPath: path)
            if picture {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(edge * 2),
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size < 200_000_000, let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: NSSize(width: edge * 2, height: edge * 2), for: .mediaBox)
        }.value
        await gate.leave()
        if let img { cachePut(cache, img, key) }
        return img
    }
}

/// A file's icon, replaced by its picture once made (only for rows that stay
/// on screen a moment: rows scrolled past ask for nothing).
struct FileIcon: View {
    let path: String
    var size: CGFloat = 28
    var thumbnail = false
    /// Unused (kept for the shared ScrubThumb).
    var large = false
    @State private var image: NSImage?
    @State private var imageFor: String?
    @State private var icon: NSImage?
    @State private var iconFor: String?

    var body: some View {
        Image(nsImage: (imageFor == path ? image : nil) ?? (iconFor == path ? icon : nil) ?? Thumbs.shared.typeIcon(for: path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: "\(path)|\(Int(size / 64))") { await load() }
    }

    private func load() async {
        let p = path
        Thumbs.shared.ownIcon(for: p) { img in
            icon = img
            iconFor = p
        }
        guard thumbnail else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if Task.isCancelled { return }
        let step = (size / 64).rounded(.up) * 64
        let img = await Thumbs.shared.thumbnail(for: p, edge: max(size, step))
        if Task.isCancelled { return }
        image = img
        imageFor = p
    }
}

/// Quick Look (Space, ⌘Y): the selected file, ← → through the results.
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var items: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func show(_ urls: [URL], at index: Int) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        items = urls
        panel.updateController()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    func close() {
        if isVisible, let panel = QLPreviewPanel.shared() { panel.close() }
    }

    func toggle(_ urls: [URL], at index: Int) {
        if isVisible { close() } else { show(urls, at: index) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.keyCode == 49 {
            close()
            return true
        }
        return false
    }
}
