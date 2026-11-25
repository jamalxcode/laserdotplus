import AppKit
import SwiftUI

/// Drag-to-select in the picture views (grid, contact sheet, timeline), as in
/// Finder and Laserdot: a box drawn over the files selects what it touches,
/// live; ⌘ or ⇧ adds to the selection. A drag that starts on a selected file
/// drags the file out instead (to Finder, Mail…).
struct MarqueeSelect: ViewModifier {
    @ObservedObject var model: LibraryModel
    @State private var frames = TileFrames()
    @State private var box: CGRect?
    @State private var base: Set<String> = []
    @State private var state = MarqueeState.idle
    /// Where the tiles on screen are (the self-test draws a box over them).
    static var lastFrames: [String: CGRect] = [:]

    /// The files a box touches.
    static func touched(_ frames: [String: CGRect], by box: CGRect) -> [String] {
        frames.filter { $0.value.intersects(box) }.map(\.key)
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .coordinateSpace(.named(TileFrames.space))
            .onPreferenceChange(TileFramesKey.self) {
                frames.frames = $0
                MarqueeSelect.lastFrames = $0
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(TileFrames.space))
                    .onChanged(step)
                    .onEnded { _ in
                        box = nil
                        state = .idle
                    }
            )
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

    private func step(_ v: DragGesture.Value) {
        if state == .idle {
            let onSelected = frames.frames.contains { model.selection.contains($0.key) && $0.value.contains(v.startLocation) }
            if onSelected {
                state = .ignored // the file is being dragged out
                return
            }
            state = .drawing
            let flags = NSEvent.modifierFlags
            base = flags.contains(.command) || flags.contains(.shift) ? model.selection : []
        }
        guard state == .drawing else { return }
        let r = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                       width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
        box = r
        let touched = Self.touched(frames.frames, by: r)
        let next = base.union(touched)
        if next != model.selection { model.selection = next }
    }
}

enum MarqueeState { case idle, drawing, ignored }

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

extension View {
    /// Reports this file's tile to the drag-to-select box.
    func tileFrame(_ path: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: TileFramesKey.self, value: [path: g.frame(in: .named(TileFrames.space))])
        })
    }

    /// Drag-to-select for a picture view's contents.
    func marqueeSelect(_ model: LibraryModel) -> some View { modifier(MarqueeSelect(model: model)) }

    /// A selected file can be dragged out (to Finder, Mail…); dragging
    /// anywhere else draws the selection box.
    @ViewBuilder func fileDrag(_ path: String, when selected: Bool) -> some View {
        if selected {
            onDrag { NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
        } else {
            self
        }
    }
}
