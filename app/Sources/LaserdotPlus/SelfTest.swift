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
        // A hard stop: a stuck step still writes the report.
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) { self.finish("timed out") }
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
                    self.model.clearFilters()
                    self.model.viewMode = .list
                    self.details()
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
        model.place = .thisMac
        waitFor(10, { !self.model.results.isEmpty }) { _ in
            self.report["this_mac_count"] = self.model.results.count
            self.report["drives"] = self.drives.drives.map(\.name)
            self.finish("")
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
