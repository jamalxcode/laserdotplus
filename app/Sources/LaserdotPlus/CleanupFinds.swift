import AppKit
import LaserdotKit
import SwiftUI

/// Clean Up ▸ Broken: pictures, videos and songs that can't be what they say
/// (empty, unreadable header, a video without a picture, no length) — from the
/// index, so it is quick on any drive. Nothing is ticked: you choose.
final class BrokenModel: ObservableObject {
    enum Phase { case idle, scanning, done }
    @Published var phase = Phase.idle
    @Published var items: [BrokenItem] = []
    @Published var chosen: Set<String> = []
    @Published var problem: String?
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    var chosenBytes: UInt64 { items.filter { chosen.contains($0.path) }.reduce(0) { $0 + $1.size } }

    func scan(place: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        problem = nil
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = Result { try engine.broken(scope: place) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch r {
                case let .success(found): self.items = found
                case let .failure(e): self.items = []; self.problem = (e as? LaserdotError)?.message ?? e.localizedDescription
                }
                self.chosen = []
                self.phase = .done
            }
        }
    }
}

/// Clean Up ▸ Probably Unwanted: files most people would not keep — clips of a
/// few seconds, tiny or very low-quality videos, tiny pictures, screenshots —
/// found with ordinary searches of the index. A list to look through; nothing
/// is ticked and nothing moves by itself.
final class UnwantedModel: ObservableObject {
    struct Find: Hashable {
        let hit: Hit
        let why: String
    }
    enum Phase { case idle, scanning, done }
    @Published var phase = Phase.idle
    @Published var items: [Find] = []
    @Published var chosen: Set<String> = []
    let engine: Engine
    init(engine: Engine) { self.engine = engine }

    /// Each reason and its search (the filters every search has).
    static let rules: [(why: String, query: String)] = [
        ("short", "kind:video duration:<3s"),
        ("tinyVideo", "kind:video height:<240"),
        ("lowQuality", "kind:video bitrate:<300kbps"),
        ("screenshot", "screenshot:true"),
        ("tinyPicture", "kind:image width:<160 height:<160"),
    ]

    var chosenBytes: UInt64 { items.filter { chosen.contains($0.hit.path) }.reduce(0) { $0 + $1.hit.size } }

    func scan(place: String) {
        guard phase != .scanning else { return }
        phase = .scanning
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var seen = Set<String>()
            var out: [Find] = []
            for r in Self.rules {
                let q = [place, r.query].filter { !$0.isEmpty }.joined(separator: " ")
                for h in (try? engine.search(query: q, limit: 2000, sort: .size, reverse: false))?.hits ?? []
                where !h.isDir && seen.insert(h.path).inserted {
                    out.append(Find(hit: h, why: r.why))
                }
            }
            DispatchQueue.main.async {
                self?.items = out.sorted { $0.hit.size > $1.hit.size }
                self?.chosen = []
                self?.phase = .done
            }
        }
    }
}

/// The two lists' screens (inside Clean Up).
struct BrokenView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var broken: BrokenModel
    let row: (String, UInt64, String, Bool, @escaping () -> Void) -> AnyView
    let footer: (Int, UInt64, @escaping () -> Void) -> AnyView
    @Environment(\.undoManager) private var undo

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "bandage", title: L("broken.title"), detail: model.placeTitle, done: { model.showDupes = false }) {
                Button(broken.phase == .idle ? L("cleanup.find") : L("dupes.again")) { broken.scan(place: model.dupesScope) }
                    .disabled(broken.phase == .scanning)
            }
            Divider()
            switch broken.phase {
            case .idle: empty("bandage", L("broken.intro"))
            case .scanning: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                if let p = broken.problem {
                    empty("exclamationmark.triangle", p)
                } else if broken.items.isEmpty {
                    empty("checkmark.circle", L("broken.none"))
                } else {
                    List(broken.items, id: \.path) { b in
                        row(b.path, b.size, L("broken.why." + b.why), broken.chosen.contains(b.path)) {
                            if broken.chosen.contains(b.path) { broken.chosen.remove(b.path) } else { broken.chosen.insert(b.path) }
                        }
                    }
                    footer(broken.chosen.count, broken.chosenBytes) {
                        // Off the main thread: thousands of files must not freeze the window.
                        let paths = Array(broken.chosen)
                        model.trashInBackground(paths, undo: undo) { gone, _ in
                            broken.items.removeAll { gone.contains($0.path) }
                            broken.chosen.subtract(gone)
                        }
                    }
                }
            }
        }
    }

    private func empty(_ symbol: String, _ text: String) -> some View {
        ContentUnavailableView { Image(systemName: symbol) } description: { Text(text) }
    }
}

struct UnwantedView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var unwanted: UnwantedModel
    let row: (String, UInt64, String, Bool, @escaping () -> Void) -> AnyView
    let footer: (Int, UInt64, @escaping () -> Void) -> AnyView
    @Environment(\.undoManager) private var undo

    var body: some View {
        VStack(spacing: 0) {
            ModeHeader(symbol: "hand.thumbsdown", title: L("unwanted.title"), detail: model.placeTitle, done: { model.showDupes = false }) {
                Button(unwanted.phase == .idle ? L("cleanup.find") : L("dupes.again")) { unwanted.scan(place: model.dupesScope) }
                    .disabled(unwanted.phase == .scanning)
            }
            Divider()
            switch unwanted.phase {
            case .idle: empty("hand.thumbsdown", L("unwanted.intro"))
            case .scanning: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                if unwanted.items.isEmpty {
                    empty("checkmark.circle", L("unwanted.none"))
                } else {
                    List(unwanted.items, id: \.hit.path) { f in
                        row(f.hit.path, f.hit.size, L("unwanted.why." + f.why), unwanted.chosen.contains(f.hit.path)) {
                            if unwanted.chosen.contains(f.hit.path) { unwanted.chosen.remove(f.hit.path) } else { unwanted.chosen.insert(f.hit.path) }
                        }
                    }
                    footer(unwanted.chosen.count, unwanted.chosenBytes) {
                        // Off the main thread: thousands of files must not freeze the window.
                        let paths = Array(unwanted.chosen)
                        model.trashInBackground(paths, undo: undo) { gone, _ in
                            unwanted.items.removeAll { gone.contains($0.hit.path) }
                            unwanted.chosen.subtract(gone)
                        }
                    }
                }
            }
        }
    }

    private func empty(_ symbol: String, _ text: String) -> some View {
        ContentUnavailableView { Image(systemName: symbol) } description: { Text(text) }
    }
}
