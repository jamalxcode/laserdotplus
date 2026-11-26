import AppKit
import LaserdotKit
import Quartz
import SwiftUI

/// Laserdot+: one window to review a large collection of files on whatever
/// drives are plugged in — see what a file is when its name doesn't say,
/// clear out junk, remove duplicates. An ordinary app (no menu-bar item).
@main
struct LaserdotPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var updates = Updates.shared

    var body: some Scene {
        Window("Laserdot+", id: "main") {
            MainView(model: delegate.model, drives: delegate.drives)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("updates.check")) { Updates.shared.check() }
                Toggle(L("updates.daily"), isOn: $updates.daily)
            }
            CommandGroup(after: .pasteboard) {
                Button(L("menu.selectAll")) { delegate.model.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .option])
            }
            CommandGroup(after: .newItem) {
                Button(L("menu.indexFolder")) { delegate.model.chooseFolderToIndex() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(L("dupes.menu")) { delegate.model.openCleanup(.duplicates) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            // Into macOS's own View menu (a second one was added beside it).
            CommandGroup(before: .toolbar) {
                Button(L("view.list")) { delegate.model.viewMode = .list }.keyboardShortcut("1")
                Button(L("view.grid")) { delegate.model.viewMode = .grid }.keyboardShortcut("2")
                Button(L("view.sheet")) { delegate.model.viewMode = .sheet }.keyboardShortcut("3")
                Button(L("view.timeline")) { delegate.model.viewMode = .timeline }.keyboardShortcut("4")
                Divider()
                Button(L("review.start")) { delegate.model.startReview() }.keyboardShortcut("r")
                Button(L("sweep.menu")) { delegate.model.startSweep() }.keyboardShortcut("e")
                Divider()
                Button(L("action.quickLook")) { delegate.model.quickLook() }.keyboardShortcut("y")
                Button(L("filters.clear")) { delegate.model.clearFilters() }.keyboardShortcut(.delete, modifiers: [.command, .option])
                Divider()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine: Engine
    let model: LibraryModel
    let drives: DrivesModel
    private var selfTest: SelfTestRunner?

    override init() {
        // The engine (laserdotd) is bundled beside the app and denies itself
        // the network before anything else; the app has no network code.
        let db = Paths.defaultDbPath
        try? FileManager.default.createDirectory(atPath: Paths.socketDir(forDb: db), withIntermediateDirectories: true)
        let daemon = Bundle.main.url(forAuxiliaryExecutable: "laserdotd")?.path
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        engine = Engine(dbPath: db, daemonPath: daemon, expectedVersion: version)
        model = LibraryModel(engine: engine)
        drives = DrivesModel(engine: engine)
        super.init()
        drives.onChange = { [weak model] in model?.drivesChanged() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model.start()
        drives.start()
        NotificationCenter.default.addObserver(forName: .updateProgress, object: nil, queue: .main) { [weak self] n in
            self?.model.notice = n.object as? String
        }
        Updates.shared.startChecking()
        if let out = SelfTest.outDir {
            selfTest = SelfTestRunner(model: model, drives: drives, out: out)
            selfTest?.run()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting never waits on the engine on the main thread (it showed a
    /// beachball): the window goes at once, the engine is asked to stop in
    /// the background (it finishes saving on its own), then the app quits.
    private var stopping = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if stopping { return .terminateNow }
        stopping = true
        NSApp.windows.forEach { $0.orderOut(nil) }
        let engine = self.engine
        DispatchQueue.global(qos: .userInitiated).async {
            engine.shutdown(waitForExit: false)
            // Not DispatchQueue.main: when the quit started inside a main-queue
            // block (Install and Relaunch, the self-test), that queue is busy
            // until the quit ends and the answer never came — a beachball and
            // no quitting. The run loop, in the modes AppKit waits in, always
            // takes it.
            self.performSelector(onMainThread: #selector(AppDelegate.replyTerminate), with: nil, waitUntilDone: false,
                                 modes: [RunLoop.Mode.common.rawValue, RunLoop.Mode.modalPanel.rawValue,
                                         RunLoop.Mode.eventTracking.rawValue])
        }
        return .terminateLater
    }

    @objc func replyTerminate() { NSApp.reply(toApplicationShouldTerminate: true) }

    // Quick Look (Space, ⌘Y) finds its controller here.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLook.shared
        panel.delegate = QuickLook.shared
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}
