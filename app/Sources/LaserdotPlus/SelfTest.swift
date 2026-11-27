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
    /// The fixtures, as the engine spells them (/var is /private/var on macOS).
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LASERDOT_SELFTEST_FOLDER"] ?? "")
        .resolvingSymlinksInPath().path
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
        // A second, short run in Arabic (right to left): the main window only.
        if ProcessInfo.processInfo.environment["LASERDOT_SELFTEST_QUICK"] != nil {
            waitFor(30, { self.model.results.count >= 3 }) { _ in
                self.after(3) {
                    self.shot("arabic")
                    self.finish("")
                }
            }
            return
        }
        waitFor(30, { self.model.results.count >= 3 && !self.model.groups.isEmpty }) { _ in
            self.report["all_count"] = self.model.results.count
            self.report["groups"] = self.model.groups.map(\.id)
            self.shot("list")
            // The same window in dark mode.
            NSApp.appearance = NSAppearance(named: .darkAqua)
            self.after(1) {
                self.shot("dark")
                NSApp.appearance = nil
            }
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
                    // Clicks, as the mouse makes them: a click selects one,
                    // ⌘-click adds another, ⌘-click again takes it out; a drag
                    // from empty space draws a box.
                    let tiles = frames.sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
                    if let v = MouseCatcherView.current, tiles.count >= 2 {
                        let a = tiles[0], b = tiles[1]
                        let ca = CGPoint(x: a.value.midX, y: a.value.midY), cb = CGPoint(x: b.value.midX, y: b.value.midY)
                        v.simulate(.leftMouseDown, at: ca); v.simulate(.leftMouseUp, at: ca)
                        let one = self.model.selection == [a.key]
                        v.simulate(.leftMouseDown, at: cb, flags: .command); v.simulate(.leftMouseUp, at: cb, flags: .command)
                        let two = self.model.selection == [a.key, b.key]
                        v.simulate(.leftMouseDown, at: ca, flags: .command); v.simulate(.leftMouseUp, at: ca, flags: .command)
                        let back = self.model.selection == [b.key]
                        self.report["clicks"] = [one, two, back]
                        // A double click whose second click lands on another
                        // file (the files moved) opens the first one's.
                        var opened: [String] = []
                        LibraryModel.openHook = { opened += $0.map(\.path) }
                        v.simulate(.leftMouseDown, at: ca); v.simulate(.leftMouseUp, at: ca)
                        v.simulate(.leftMouseDown, at: cb, clicks: 2); v.simulate(.leftMouseUp, at: cb, clicks: 2)
                        LibraryModel.openHook = nil
                        self.report["double_click_opens_first"] = opened == [a.key]
                        // → moves the selection to the next file.
                        v.simulate(.leftMouseDown, at: ca); v.simulate(.leftMouseUp, at: ca)
                        v.move(124)
                        self.report["arrow_moves"] = self.model.selection == [b.key]
                        let from = CGPoint(x: a.value.minX - 3, y: a.value.minY - 3)
                        let to = CGPoint(x: b.value.midX, y: b.value.midY)
                        v.simulate(.leftMouseDown, at: from)
                        v.simulate(.leftMouseDragged, at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2))
                        v.simulate(.leftMouseDragged, at: to)
                        self.report["drag_box"] = self.model.selection.count
                        v.simulate(.leftMouseUp, at: to)
                    }
                    self.model.selection = Set(MarqueeSelect.touched(frames, by: {
                        guard let first = frames.values.min(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) else { return .zero }
                        return CGRect(x: first.minX - 4, y: first.minY - 4, width: first.width * 2.2, height: first.height * 0.5)
                    }()))
                    self.after(0.5) {
                    self.report["marquee_count"] = self.model.selection.count
                    self.shot("marquee")
                    // A click put in the event queue, as macOS delivers a real one
                    // (hit-testing through SwiftUI's layers).
                    self.model.selection = []
                    let firstTile = MarqueeSelect.lastFrames.min { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
                    if let v = MouseCatcherView.current, let t = firstTile {
                        v.postClick(at: CGPoint(x: t.value.midX, y: t.value.midY))
                    }
                    self.after(1) {
                    self.report["window_click"] = firstTile.map { self.model.selection == [$0.key] } ?? false
                    // ⌘-click another, through the event queue too, and move
                    // the pointer on: both stay selected (the owner: the
                    // selection went as soon as the cursor moved).
                    let second = MarqueeSelect.lastFrames.sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }.dropFirst().first
                    if let v = MouseCatcherView.current, let s = second {
                        v.postClick(at: CGPoint(x: s.value.midX, y: s.value.midY), flags: .command, thenMove: true)
                    }
                    self.after(1.5) {
                    self.report["window_cmd_click"] = self.model.selection.count
                    self.report["selection_trace"] = LibraryModel.selectionTrace
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
        }
    }

    private func details() {
        waitFor(10, { self.model.results.contains { $0.kind == "video" } }) { _ in
            guard let v = self.model.results.first(where: { $0.kind == "video" }) else { return self.trash() }
            self.model.selection = [v.path]
            self.waitFor(15, { self.model.details?.path == v.path }) { _ in
                self.report["details_sections"] = self.model.details?.sections.map(\.id) ?? []
                self.report["dates_keys"] = self.model.details?.sections.first { $0.id == "dates" }?.rows.map(\.key) ?? []
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
        // Select All: every file of the place, loaded first if need be —
        // once the list has settled after the Trash and Undo.
        waitFor(15, { self.model.results.contains { $0.path == victim } && self.model.results.count == Int(self.model.total) }) { _ in
            self.model.selectAll()
            self.waitFor(10, { self.model.selection.count == Int(self.model.total) }) { _ in
                self.report["select_all"] = self.model.selection.count == Int(self.model.total) && self.model.total > 0
                self.model.selection = []
                self.duplicates()
            }
        }
    }

    /// Find Duplicates over everything: the fixtures' pictures are one
    /// picture at four sizes (the app icon), so a "same picture" group shows.
    private func duplicates() {
        model.showDupes = true
        model.dupes.similar = true
        model.dupes.minMB = 0 // the fixtures are small
        model.dupes.scan(scope: model.dupes.scope(place: ""))
        waitFor(60, { self.model.dupes.phase == .done }) { _ in
            self.report["dupes_groups"] = self.model.dupes.groups.count
            self.report["dupes_problem"] = self.model.dupes.problem ?? ""
            // Keep ▸ The Oldest Copy: one copy kept per group, the oldest.
            let d = self.model.dupes
            d.apply(.oldest)
            self.report["keep_oldest"] = !d.groups.isEmpty && d.groups.allSatisfy { g in
                let kept = g.files.filter { d.keep.contains($0.path) }
                return kept.count == 1 && kept[0].modified == g.files.map(\.modified).min()
            }
            d.apply(.best)
            self.after(2) {
                self.shot("duplicates")
                self.junk()
            }
        }
    }

    /// Clean Up ▸ Junk over this Mac's folders: the fixtures hold a .DS_Store,
    /// a download left unfinished two days ago and an empty folder.
    private func junk() {
        model.openCleanup(.junk)
        // Look Deeper: the whole walk (the scale step below checks the quick
        // look from the index).
        model.junk.scan(roots: model.status?.folders ?? [], deeper: true)
        waitFor(60, { self.model.junk.phase == .done }) { _ in
            self.report["junk_whys"] = Array(Set(self.model.junk.items.map(\.why))).sorted()
            self.after(1) {
                self.shot("junk")
                // Clean Up ▸ Space: the folders by size.
                self.model.openCleanup(.space)
                self.waitFor(20, { !self.model.space.items.isEmpty }) { _ in
                    self.report["space_items"] = self.model.space.items.count
                    self.after(1) {
                        self.shot("space")
                        self.model.showDupes = false
                        self.review()
                    }
                }
            }
        }
    }

    private func review() {
        // Review mode: T marks for the Trash (into the tray), K keeps.
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
                self.sweep()
            }
        }
    }

    /// "What is this?": only the unclear names (IMG_000x, VID_2034), each
    /// with a suggested name once its details are read.
    private func sweep() {
        model.clearFilters()
        // The kinds' colour-blind-safe colours: each its own; file types take their kind's.
        report["kind_colors"] = Set(["video", "image", "audio", "document", "folder", "archive"].map { "\(Palette.kind($0))" }).count
        report["type_kinds"] = ["mp4", "png", "txt", "csv", "mp3", "zip"].map(Palette.kind(ofExtension:))
        waitFor(10, { self.model.results.count >= 10 }) { _ in
            self.model.startSweep()
            self.report["sweep_names"] = self.model.sweep?.map(\.name).sorted() ?? []
            self.waitFor(30, { self.model.sweep?.first.map { self.model.suggestedName($0) != nil } ?? false }) { _ in
                self.report["sweep_suggestion"] = self.model.sweep?.first.flatMap { self.model.suggestedName($0) } ?? ""
                self.after(2) {
                    self.shot("sweep")
                    self.model.reviewIndex = nil
                    self.thisMac()
                }
            }
        }
    }

    private func thisMac() {
        model.allChoices = true // the "place" screenshot shows all the choices
        report["inspector_shown"] = model.showInspector
        model.place = .thisMac
        let gone = folder + "/Trips/2023/rome trip.txt"
        // Matched by its end: the engine may spell the folder differently
        // (/var or /private/var).
        let isGone: (Hit) -> Bool = { $0.path.hasSuffix("/Trips/2023/rome trip.txt") }
        waitFor(10, { self.model.results.contains(where: isGone) }) { _ in
            self.report["this_mac_count"] = self.model.results.count
            // The chosen place shows in the search box as a pill.
            self.report["place_pill"] = self.model.pills.first { $0.isPlace }?.label ?? ""
            // All the choices: what can be chosen leads, what cannot is small.
            let arranged = RefineLogic.arranged(self.model.openGroups)
            self.report["choices_arranged"] = arranged.allSatisfy { g in
                guard let dead = g.options.firstIndex(where: { $0.count == 0 }) else { return true }
                return g.options[dead...].allSatisfy { $0.count == 0 }
            }
            self.shot("place")
            self.model.allChoices = false
            self.report["drives"] = self.drives.drives.map(\.name)
            // Deleted behind the app's back (as in Finder): it leaves the list.
            self.report["external_listed"] = self.model.results.contains(where: isGone)
            // Paths read like Finder's: no /private, no system folders.
            self.report["friendly_path"] = friendlyPath(gone)
            self.report["external_paths"] = self.model.results.map(\.path).filter { $0.contains("trip") }
            try? FileManager.default.removeItem(atPath: gone)
            self.waitFor(25, { !self.model.results.contains(where: isGone) }) { ok in
                self.report["external_delete"] = ok
                self.driveDelete()
            }
        }
    }

    /// On the plugged-in drive (exFAT, like the owner's T5 EVO): a file
    /// deleted behind the app's back leaves the list too.
    private func driveDelete() {
        model.place = .drive("LDPlus")
        let isSpare: (Hit) -> Bool = { $0.path.hasSuffix("/Movies/spare.webm") }
        waitFor(40, { self.model.results.contains(where: isSpare) }) { listed in
            self.report["drive_listed"] = listed
            if let p = self.model.results.first(where: isSpare)?.path { try? FileManager.default.removeItem(atPath: p) }
            self.waitFor(25, { !self.model.results.contains(where: isSpare) }) { ok in
                self.report["drive_delete"] = listed && ok
                // A view saved on the drive is kept on the drive, and nowhere on this Mac.
                self.model.toggle("kind", "kind:video", label: "Videos")
                self.model.views.save(self.model.currentView(named: "Drive videos"))
                let onDrive = URL(fileURLWithPath: "/Volumes/LDPlus/.laserdot/views.json")
                let onMac = URL(fileURLWithPath: self.model.engine.dbPath).deletingLastPathComponent().appendingPathComponent("views.json")
                self.waitFor(5, { FileManager.default.fileExists(atPath: onDrive.path) }) { saved in
                    let macText = (try? String(contentsOf: onMac, encoding: .utf8)) ?? ""
                    self.report["view_on_drive"] = saved && !macText.contains("Drive videos")
                    self.integrity()
                }
            }
        }
    }

    /// Broken Files runs over everything; on the test drive, fingerprints are
    /// saved (on the drive) and checked: no damage.
    private func integrity() {
        model.broken.scan(place: "")
        let engine = model.engine
        DispatchQueue.global(qos: .userInitiated).async {
            let saved = try? engine.saveChecksums(mount: "/Volumes/LDPlus")
            let checked = try? engine.checkChecksums(mount: "/Volumes/LDPlus")
            DispatchQueue.main.async {
                self.report["checksums_saved"] = Int(saved?.files ?? 0)
                self.report["checksums_damage"] = checked.map { $0.damaged.count } ?? -1
                self.report["checksums_on_drive"] = FileManager.default.fileExists(atPath: "/Volumes/LDPlus/.laserdot/checksums.bin")
                self.waitFor(20, { self.model.broken.phase == .done }) { _ in
                    self.report["broken_ran"] = self.model.broken.phase == .done && self.model.broken.problem == nil
                    self.scale()
                }
            }
        }
    }

    /// At a real drive's scale (the critique: every freeze the owner met passed
    /// this test, which had a dozen files): 40,000 files, half of them empty
    /// (Junk finds tens of thousands), plus hidden "._" files; indexed, then
    /// searched, all selected, Junk run — the window must never stall.
    private func scale() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ldp-scale-\(UUID().uuidString.prefix(8))")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            for d in 0..<200 {
                let folder = dir.appendingPathComponent(String(format: "Folder %03d", d))
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                for f in 0..<200 {
                    let data = f % 2 == 0 ? Data() : Data("x".utf8)
                    fm.createFile(atPath: folder.appendingPathComponent(String(format: "clip %03d.txt", f)).path, contents: data)
                    if f % 8 == 0 { fm.createFile(atPath: folder.appendingPathComponent(String(format: "._clip %03d.txt", f)).path, contents: Data("j".utf8)) }
                }
            }
            DispatchQueue.main.async {
                _ = FreezeWatch.takeLongest()
                let started = Date()
                self.model.clearFilters()
                self.model.index(folder: dir.path)
                self.waitFor(180, { self.model.status?.indexing == nil && self.model.total >= 40_000 && Date().timeIntervalSince(started) > 5 }) { indexed in
                    self.report["scale_indexed"] = indexed
                    self.report["scale_files"] = Int(self.model.total)
                    self.model.text = "clip"
                    // The search for "clip" itself must be done (a search that
                    // lands after Select All rightly clears the selection):
                    // past the typing pause, then not searching.
                    self.after(1.5) {
                    self.waitFor(30, { !self.model.searching && self.model.total >= 40_000 }) { _ in
                        self.model.selectAll()
                        self.waitFor(30, { self.model.selection.count >= 40_000 }) { _ in
                            self.report["scale_selected"] = self.model.selection.count
                            self.model.junk.scan(roots: [dir.path])
                            self.waitFor(120, { self.model.junk.phase == .done }) { _ in
                                self.report["scale_junk"] = self.model.junk.items.count
                                let l = FreezeWatch.takeLongest()
                                self.report["scale_longest_stall"] = (l.seconds * 100).rounded() / 100
                                self.report["scale_stall_step"] = l.step
                                self.report["scale_memory_mb"] = Int(FreezeWatch.memoryBytes() >> 20)
                                try? FileManager.default.removeItem(at: dir)
                                self.finish("")
                            }
                        }
                    }
                    }
                }
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
        guard let w = NSApp.windows.filter({ $0.isVisible }).max(by: { $0.frame.width < $1.frame.width }) else { return }
        // As the window server draws it (the sidebar's and the inspector's
        // translucent materials too); an app may capture its own windows.
        var png: Data?
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
        if png == nil, let view = w.contentView?.superview ?? w.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            png = rep.representation(using: .png, properties: [:])
        }
        guard let png else { return }
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
