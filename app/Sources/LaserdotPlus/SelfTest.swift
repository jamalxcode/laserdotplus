import AppKit
import LaserdotKit

/// CI drives the real app (LASERDOT_SELFTEST=<folder for the report>,
/// LASERDOT_SELFTEST_FOLDER=<fixtures>): it indexes the fixtures, searches,
/// ticks filters, switches views, selects a video, moves a file to the
/// Trash and back, and writes report.json and screenshots that
/// app/scripts/check-selftest.py judges.
enum SelfTest {
    static var outDir: URL? {
        guard let p = ProcessInfo.processInfo.environment["LASERDOT_SELFTEST"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p)
    }
    static var active: Bool { outDir != nil }
}

final class SelfTestRunner {
    let model: LibraryModel
    let drives: DrivesModel
    let out: URL
    let folder = ProcessInfo.processInfo.environment["LASERDOT_SELFTEST_FOLDER"] ?? ""
    var report: [String: Any] = [:]
    var shots: [String] = []
    let undo = UndoManager()
    let started = Date()

    init(model: LibraryModel, drives: DrivesModel, out: URL) {
        self.model = model
        self.drives = drives
        self.out = out
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func run() {
        // A hard stop: a stuck step still writes the report (a run-loop
        // timer in the common modes, so it fires during mouse tracking too).
        let stop = Timer(timeInterval: 240, repeats: false) { [weak self] _ in self?.finish("timed out") }
        RunLoop.main.add(stop, forMode: .common)
        waitFor(60, { self.model.status?.running == true }) { ok in
            guard ok else { return self.finish("the engine did not start") }
            DispatchQueue.global().async {
                _ = try? self.model.engine.index(path: self.folder)
                DispatchQueue.main.async { self.steps() }
            }
        }
    }

    private func steps() {
        model.schedule(now: true)
        waitFor(30, { self.model.results.count >= 3 && !self.model.groups.isEmpty }) { _ in
            self.report["all_count"] = self.model.results.count
            self.report["groups"] = self.model.groups.map(\.id)
            self.shot("list")
            // Typing narrows.
            self.model.text = "trip"
            self.waitFor(10, { !self.model.results.isEmpty && self.model.results.allSatisfy { $0.name.lowercased().contains("trip") } }) { _ in
                self.report["typed"] = self.model.results.map(\.name).sorted()
                self.model.text = ""
                self.filters()
            }
        }
    }

    private func filters() {
        waitFor(10, { self.model.groups.contains { $0.id == "kind" } }) { _ in
            let kind = self.model.groups.first { $0.id == "kind" }
            self.report["kind_options"] = kind?.options.map(\.token) ?? []
            self.model.toggle("kind", "kind:image")
            self.waitFor(10, { !self.model.results.isEmpty && self.model.results.allSatisfy { $0.kind == "image" } }) { _ in
                self.report["filtered_kinds"] = Array(Set(self.model.results.map(\.kind)))
                self.report["filtered_query"] = self.model.effectiveQuery
                self.shot("filtered")
                self.model.viewMode = .grid
                self.after(2) {
                    self.shot("grid")
                    // Drag-to-select: a box drawn from the top-left corner across
                    // the first row of tiles (as laid out on screen) selects them.
                    self.model.selection = []
                    let frames = MarqueeSelect.lastFrames
                    if let first = frames.values.min(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) {
                        let box = CGRect(x: first.minX - 4, y: first.minY - 4, width: first.width * 2.2, height: first.height * 0.5)
                        self.model.selection = Set(MarqueeSelect.touched(frames, by: box))
                    }
                    self.after(0.5) {
                    self.report["marquee_count"] = self.model.selection.count
                    self.shot("marquee")
                    self.model.clearFilters()
                    self.model.viewMode = .sheet
                    self.after(3) {
                        self.shot("sheet")
                        self.model.viewMode = .timeline
                        self.after(2) {
                            self.shot("timeline")
                            self.report["months"] = self.model.months.map(\.title)
                            self.model.viewMode = .list
                            self.details()
                        }
                    }
                    }
                }
            }
        }
    }

    private func details() {
        waitFor(10, { self.model.results.contains { $0.kind == "video" } }) { _ in
            guard let v = self.model.results.first(where: { $0.kind == "video" }) else { return self.trash() }
            self.model.selection = [v.path]
            self.waitFor(15, { self.model.details?.path == v.path }) { _ in
                self.report["details_sections"] = self.model.details?.sections.map(\.id) ?? []
                self.after(3) { // the storyboard's frames
                    self.shot("details")
                    self.trash()
                }
            }
        }
    }

    private func trash() {
        let victim = folder + "/trashme.txt"
        model.trashPaths([victim], undo: undo)
        report["trashed"] = !FileManager.default.fileExists(atPath: victim)
        report["trash_hidden"] = !model.results.contains { $0.path == victim }
        undo.undo()
        report["restored"] = FileManager.default.fileExists(atPath: victim)
        // Review mode: T marks for the Trash (into the tray), K keeps.
        // Select All: every file of the place, loaded first if need be.
        model.selectAll()
        report["select_all"] = model.selection.count == Int(model.total) && model.total > 0
        model.selection = []
        model.startReview()
        model.reviewDecide(.trash)
        model.reviewDecide(nil)
        report["tray_count"] = model.tray.count
        report["review_index"] = model.reviewIndex ?? -1
        after(2) {
            self.shot("review")
            self.model.reviewIndex = nil
            self.after(1) {
                self.shot("tray")
                self.model.clearTray()
                self.thisMac()
            }
        }
    }

    private func thisMac() {
        model.place = .thisMac
        waitFor(10, { !self.model.results.isEmpty }) { _ in
            self.report["this_mac_count"] = self.model.results.count
            // The chosen place shows in the search box as a pill.
            self.report["place_pill"] = self.model.pills.first { $0.isPlace }?.label ?? ""
            self.shot("place")
            self.report["drives"] = self.drives.drives.map(\.name)
            // Deleted behind the app's back (as in Finder): it leaves the list.
            let gone = self.folder + "/Trips/2023/rome trip.txt"
            self.report["external_listed"] = self.model.results.contains { $0.path == gone }
            try? FileManager.default.removeItem(atPath: gone)
            self.waitFor(25, { !self.model.results.contains { $0.path == gone } }) { ok in
                self.report["external_delete"] = ok
                self.finish("")
            }
        }
    }

    // MARK: helpers

    private func waitFor(_ seconds: Double, _ ready: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(seconds)
        func check() {
            if ready() { return then(true) }
            if Date() > deadline { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: check)
        }
        check()
    }

    private func after(_ seconds: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: f)
    }

    private func shot(_ name: String) {
        guard let w = NSApp.windows.filter({ $0.isVisible }).max(by: { $0.frame.width < $1.frame.width }),
              let view = w.contentView?.superview ?? w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: out.appendingPathComponent(name + ".png"))
        shots.append(name)
    }

    private var finished = false
    private func finish(_ error: String) {
        guard !finished else { return }
        finished = true
        report["error"] = error
        report["screenshots"] = shots
        report["seconds"] = Int(Date().timeIntervalSince(started))
        report["network_denied"] = model.status?.networkDenied ?? false
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("report.json"))
        }
        NSApp.terminate(nil)
    }
}
