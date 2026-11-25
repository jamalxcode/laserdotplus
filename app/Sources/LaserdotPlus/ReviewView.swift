import LaserdotKit
import SwiftUI

/// Review mode: the results one at a time, full-window. ← → move, Space
/// plays it in Quick Look, K keeps, T marks for the Trash, M marks to move
/// (into the clean-up tray; nothing moves until the tray is applied), Esc
/// closes.
struct ReviewView: View {
    @ObservedObject var model: LibraryModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if let i = model.reviewIndex, model.results.indices.contains(i) {
                let h = model.results[i]
                HStack {
                    Text(String(format: L("review.position"), i + 1, model.total)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button(L("review.done")) { model.reviewIndex = nil }.keyboardShortcut(.cancelAction)
                }
                Group {
                    if h.kind == "video" {
                        ScrubThumb(path: h.path, size: 640)
                        FrameStrip(path: h.path, count: 10, height: 70)
                    } else {
                        FileIcon(path: h.path, size: 600, thumbnail: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 4) {
                    Text(h.name).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(([kindText(h.kind), bytesText(h.size), dateText(h.modified)] + h.badges).joined(separator: " · "))
                        .foregroundStyle(.secondary).lineLimit(1)
                    Text(whereText(h.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                    Button { model.reviewStep(-1) } label: { Label(L("review.previous"), systemImage: "chevron.left") }
                    decision(L("review.keep"), "K", nil, h)
                    decision(L("review.trash"), "T", .trash, h)
                    decision(L("review.move"), "M", .move, h)
                    Button { model.reviewStep(1) } label: { Label(L("review.next"), systemImage: "chevron.right") }
                }
                .controlSize(.large)
                Text(L("review.keys")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { model.reviewStep(-1); return .handled }
        .onKeyPress(.rightArrow) { model.reviewStep(1); return .handled }
        .onKeyPress(.space) { model.quickLook(); return .handled }
        .onKeyPress(.escape) { model.reviewIndex = nil; return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "ktmKTM")) { press in
            switch press.characters.lowercased() {
            case "k": model.reviewDecide(nil)
            case "t": model.reviewDecide(.trash)
            default: model.reviewDecide(.move)
            }
            return .handled
        }
    }

    private func decision(_ title: String, _ key: String, _ action: TrayAction?, _ h: Hit) -> some View {
        let marked = model.tray[h.path]?.action
        let on = action == nil ? marked == nil : marked == action
        return Button {
            model.reviewDecide(action)
        } label: {
            Text("\(title)  \(key)")
                .frame(minWidth: 90)
        }
        .buttonStyle(.borderedProminent)
        .tint(on ? (action == .trash ? Color.red : action == .move ? Color.orange : Color.accentColor) : Color.gray)
    }
}

/// The clean-up tray, under the files while it holds something.
struct TrayBar: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.undoManager) private var undo
    @State private var showList = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
            Text(String(format: L("tray.summary"), model.tray.count, bytesText(model.trayBytes),
                        model.trayCount(.trash), model.trayCount(.move)))
                .monospacedDigit()
            Spacer()
            Button(L("tray.show")) { showList.toggle() }
                .popover(isPresented: $showList) { TrayList(model: model) }
            Button(L("tray.clear")) { model.clearTray() }
            Button(L("tray.apply")) { model.applyTray(undo: undo) }
                .buttonStyle(.borderedProminent)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.10))
    }
}

/// What the tray holds, with a way to take each out.
struct TrayList: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        let items = model.tray.values.sorted { $0.hit.name < $1.hit.name }
        List {
            ForEach(items, id: \.hit.path) { item in
                HStack {
                    Image(systemName: item.action == .trash ? "trash" : "folder")
                        .foregroundStyle(item.action == .trash ? Color.red : Color.orange)
                    FileIcon(path: item.hit.path, size: 18)
                    Text(item.hit.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(bytesText(item.hit.size)).foregroundStyle(.secondary).monospacedDigit()
                    Button { model.unmark([item.hit.path]) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .frame(width: 460, height: 320)
    }
}
