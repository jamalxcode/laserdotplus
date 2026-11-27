import AppKit
import SwiftUI

/// Clicking and drag-to-select in the picture views (grid, contact sheet,
/// timeline), as in Finder: a click selects, ⌘-click adds or removes one,
/// ⇧-click selects a range, a double click opens; a box drawn from empty space
/// or an unselected file selects what it touches, live (⌘ or ⇧ adds to the
/// selection); dragging a selected file drags all the selected files out (to
/// Finder, Mail…). ⌫ or ⌘⌫ moves the selection to the Trash, Return opens it,
/// Space shows it in Quick Look.
///
/// Done with AppKit's mouse events on one view laid over the files (the owner:
/// "command click does not work for individual selections, drag select with
/// mouse also doesn't work properly"): SwiftUI's tap gestures read the keys
/// late and lost clicks when a tile changed on being selected. Right-click,
/// control-click and hovering go through to the tiles (menus, video scrub).
struct MarqueeSelect: ViewModifier {
    @ObservedObject var model: LibraryModel
    @State private var frames = TileFrames()
    @State private var box: CGRect?
    /// Where the tiles on screen are (the self-test draws a box over them).
    static var lastFrames: [String: CGRect] = [:]

    /// The files a box touches.
    static func touched(_ frames: [String: CGRect], by box: CGRect) -> [String] {
        frames.filter { $0.value.intersects(box) }.map(\.key)
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .coordinateSpace(.named(TileFrames.space))
            .onPreferenceChange(TileFramesKey.self) {
                frames.frames = $0
                MarqueeSelect.lastFrames = $0
            }
            .overlay(MouseCatcher(model: model, frames: frames, box: $box))
            .overlay(alignment: .topLeading) {
                if let r = box {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Where each file's tile is (only those on screen: the grids are lazy).
/// A class so that scrolling does not redraw the view.
final class TileFrames {
    static let space = "tiles"
    var frames: [String: CGRect] = [:]
}

struct TileFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct MouseCatcher: NSViewRepresentable {
    let model: LibraryModel
    let frames: TileFrames
    @Binding var box: CGRect?

    func makeNSView(context: Context) -> MouseCatcherView {
        let v = MouseCatcherView()
        MouseCatcherView.current = v
        v.model = model
        v.frames = frames
        v.setBox = { box = $0 }
        return v
    }

    func updateNSView(_ v: MouseCatcherView, context: Context) {
        v.model = model
        v.frames = frames
        v.setBox = { box = $0 }
    }
}

final class MouseCatcherView: NSView, NSDraggingSource {
    /// The one on screen (the self-test clicks it with real mouse events).
    static weak var current: MouseCatcherView?
    weak var model: LibraryModel?
    var frames = TileFrames()
    var setBox: (CGRect?) -> Void = { _ in }

    private enum Drag { case none, pending(String), marquee(Set<String>), out }
    private var drag = Drag.none
    private var start = CGPoint.zero
    /// Where ⇧-click ranges start (a file, so it survives new results).
    private var anchor: String?
    /// The file the last click landed on: a double click opens that one,
    /// even if the files moved between its two clicks.
    private var lastClick: (path: String, time: TimeInterval)?

    override var isFlipped: Bool { true } // the same coordinates as the tiles'
    override func isAccessibilityElement() -> Bool { false } // VoiceOver reads the tiles under it
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func tile(at p: CGPoint) -> String? {
        frames.frames.first { $0.value.contains(p) }?.key
    }

    /// Only the left button's clicks and drags, over the files: menus,
    /// hovering, the scroll wheel and "Load more" below go through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let e = NSApp.currentEvent, let sv = superview else { return nil }
        switch e.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            if e.type == .leftMouseDown, e.modifierFlags.contains(.control) { return nil } // a context menu
            let p = convert(point, from: sv)
            let bottom = frames.frames.values.map(\.maxY).max() ?? 0
            // Below the files: "Load more" takes its own clicks; without it, a
            // click there empties the selection, as in Finder.
            guard bounds.contains(p), p.y <= bottom + 12 || !(model?.canLoadMore ?? true) else { return nil }
            return self
        default:
            return nil
        }
    }

    override func mouseDown(with e: NSEvent) {
        guard let model else { return }
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        start = p
        let hit = tile(at: p)
        let flags = e.modifierFlags
        let adding = flags.contains(.command) || flags.contains(.shift)

        if e.clickCount >= 2 {
            let first = lastClick.flatMap { e.timestamp - $0.time <= NSEvent.doubleClickInterval + 0.1 ? $0.path : nil }
            if let path = first ?? hit {
                drag = .none
                lastClick = nil
                model.selectOne(path)
                model.open(model.results.filter { $0.path == path })
                return
            }
        }
        lastClick = hit.map { ($0, e.timestamp) }
        guard let hit else {
            // Empty space: a box (or, if it is only a click, nothing selected).
            drag = .marquee(adding ? model.selection : [])
            if !adding { model.selection = [] }
            return
        }
        if flags.contains(.command) {
            if model.selection.contains(hit) { model.selection.remove(hit) } else { model.selection.insert(hit) }
            anchor = hit
            drag = .marquee(model.selection)
            return
        }
        if flags.contains(.shift), let a = anchor,
           let ai = model.results.firstIndex(where: { $0.path == a }),
           let hi = model.results.firstIndex(where: { $0.path == hit }) {
            model.selection = Set(model.results[min(ai, hi)...max(ai, hi)].map(\.path))
            drag = .marquee(model.selection)
            return
        }
        if model.selection.contains(hit) {
            // A drag takes the selected files out; a click alone selects this one.
            drag = .pending(hit)
            return
        }
        model.selectOne(hit)
        anchor = hit
        drag = .marquee([])
    }

    override func mouseDragged(with e: NSEvent) {
        guard let model else { return }
        let p = convert(e.locationInWindow, from: nil)
        switch drag {
        case .pending:
            guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
            drag = .out
            dragOut(model.selectedHits.map(\.path), with: e)
        case let .marquee(base):
            guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
            autoscroll(with: e)
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            setBox(r)
            let next = base.union(MarqueeSelect.touched(frames.frames, by: r))
            if next != model.selection { model.selection = next }
        case .none, .out:
            break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if case let .pending(hit) = drag {
            model?.selectOne(hit)
            anchor = hit
        }
        drag = .none
        setBox(nil)
    }

    /// A click put in the app's event queue, as macOS delivers a real one:
    /// it is taken from the queue and routed by hit-testing (the self-test
    /// checks that clicks reach this view through SwiftUI's layers).
    func postClick(at p: CGPoint, flags: NSEvent.ModifierFlags = [], thenMove: Bool = false) {
        guard let w = window else { return }
        let loc = convert(p, to: nil)
        var types: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp]
        if thenMove { types += [.mouseMoved, .mouseMoved] } // the pointer moves on, as the owner's did
        for (i, type) in types.enumerated() {
            let at = type == .mouseMoved ? CGPoint(x: loc.x + CGFloat(i) * 6, y: loc.y) : loc
            if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: type == .mouseMoved ? [] : flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    /// A click or drag as the mouse would make it, at tile coordinates (the
    /// self-test: the events go straight to this view's handlers).
    func simulate(_ type: NSEvent.EventType, at p: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
        guard let w = window, let e = NSEvent.mouseEvent(with: type, location: convert(p, to: nil), modifierFlags: flags,
                                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
        switch type {
        case .leftMouseDown: mouseDown(with: e)
        case .leftMouseDragged: mouseDragged(with: e)
        default: mouseUp(with: e)
        }
    }

    // MARK: dragging files out

    private func dragOut(_ paths: [String], with e: NSEvent) {
        guard !paths.isEmpty else { return }
        let p = convert(e.locationInWindow, from: nil)
        let items = paths.prefix(500).enumerated().map { i, path -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: path) // the type's icon: no file is read for a picture
            let o = CGFloat(min(i, 4)) * 4
            item.setDraggingFrame(CGRect(x: p.x - 24 + o, y: p.y - 24 + o, width: 48, height: 48), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: e, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : .move // inside: onto a drive in the sidebar
    }

    // MARK: keys, once a file was clicked

    override func keyDown(with e: NSEvent) {
        // Review and Clean Up cover the files: their keys are theirs (⌫ must
        // never trash a file that is not on screen).
        guard let model, model.reviewIndex == nil, !model.showDupes else { return super.keyDown(with: e) }
        switch e.keyCode {
        case 51, 117: // ⌫, ⌦ (with or without ⌘)
            model.trashSelected(model.selectedHits, undo: undoManager)
        case 36, 76: // Return, Enter
            model.open(model.selectedHits)
        case 49: // Space
            model.quickLook()
        case 123, 124, 125, 126: // ← → ↓ ↑
            move(e.keyCode)
        default:
            super.keyDown(with: e)
        }
    }

    /// The arrows move the selection, as in Finder's icon view: ← → to the
    /// file before or after, ↑ ↓ to the one above or below.
    func move(_ key: UInt16) {
        guard let model, !model.results.isEmpty else { return }
        let paths = model.results.map(\.path)
        let current = anchor.flatMap { model.selection.contains($0) ? $0 : nil } ?? model.selection.first
        guard let cur = current, let i = paths.firstIndex(of: cur) else {
            select(paths[0])
            return
        }
        var target: String?
        switch key {
        case 123: target = i > 0 ? paths[i - 1] : nil
        case 124: target = i + 1 < paths.count ? paths[i + 1] : nil
        default:
            if let f = frames.frames[cur] {
                let down = key == 125
                let row = frames.frames.filter { down ? $0.value.minY > f.maxY - 1 : $0.value.maxY < f.minY + 1 }
                let nextY = down ? row.values.map(\.minY).min() : row.values.map(\.minY).max()
                if let y = nextY {
                    target = row.filter { abs($0.value.minY - y) < 2 }
                        .min { abs($0.value.midX - f.midX) < abs($1.value.midX - f.midX) }?.key
                }
            }
            if target == nil { // not laid out yet: a row's worth
                let perRow = max(1, frames.frames.values.filter { abs($0.minY - (frames.frames[cur]?.minY ?? 0)) < 2 }.count)
                let j = key == 125 ? i + perRow : i - perRow
                target = paths.indices.contains(j) ? paths[j] : nil
            }
        }
        if let t = target { select(t) }
    }

    private func select(_ path: String) {
        model?.selectOne(path)
        anchor = path
        if let f = frames.frames[path] { scrollToVisible(f.insetBy(dx: 0, dy: -12)) }
    }
}

extension View {
    /// Reports this file's tile to the drag-to-select box.
    func tileFrame(_ path: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: TileFramesKey.self, value: [path: g.frame(in: .named(TileFrames.space))])
        })
    }

    /// Clicking and drag-to-select for a picture view's contents.
    func marqueeSelect(_ model: LibraryModel) -> some View { modifier(MarqueeSelect(model: model)) }
}
