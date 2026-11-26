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
            }
            FileCommands(model: delegate.model)
            CommandGroup(after: .pasteboard) {
                Button(L("menu.find")) { delegate.model.focusSearch += 1 }
                    .keyboardShortcut("f")
                Button(L("menu.selectAll")) { delegate.model.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .option])
            }
            // Into macOS's own View menu (a second one was added beside it).
            CommandGroup(before: .toolbar) {
                Button(L("view.list")) { delegate.model.viewMode = .list }.keyboardShortcut("1")
                Button(L("view.grid")) { delegate.model.viewMode = .grid }.keyboardShortcut("2")
                Button(L("view.sheet")) { delegate.model.viewMode = .sheet }.keyboardShortcut("3")
                Button(L("view.timeline")) { delegate.model.viewMode = .timeline }.keyboardShortcut("4")
                Divider()
                Button(L("inspector.toggle")) { delegate.model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button(L("filters.clear")) { delegate.model.clearFilters() }.keyboardShortcut(.delete, modifiers: [.command, .option])
                Divider()
            }
            CommandMenu(L("tools.title")) {
                Button(L("sweep.menu")) { delegate.model.startSweep() }.keyboardShortcut("e")
                Button(L("review.start")) { delegate.model.startReview() }.keyboardShortcut("r")
                Divider()
                Button(L("dupes.menu")) { delegate.model.openCleanup(.duplicates) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button(L("cleanup.junk.menu")) { delegate.model.openCleanup(.junk) }.keyboardShortcut("j", modifiers: [.command, .shift])
                Button(L("cleanup.bigOld.menu")) { delegate.model.openCleanup(.bigOld) }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button(L("space.menu")) { delegate.model.openCleanup(.space) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("broken.title")) { delegate.model.openCleanup(.broken) }
                Button(L("unwanted.title")) { delegate.model.openCleanup(.unwanted) }
            }
            CommandGroup(replacing: .help) {
                Button(L("shortcuts.title")) { WhatsNew.showShortcuts() }.keyboardShortcut("/", modifiers: .command)
                Button(L("whatsNew.menu")) { WhatsNew.show(after: nil) }
            }
        }
        // Settings… (⌘,), as every Mac app has.
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

/// The File menu, as in Finder: open, open with, info, rename, look, show,
/// copy, Trash — for the selected files.
struct FileCommands: Commands {
    @ObservedObject var model: LibraryModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            let hits = model.selectedHits
            let undo = NSApp.keyWindow?.undoManager
            Button(L("action.open")) { model.open(hits) }
                .keyboardShortcut("o")
                .disabled(hits.isEmpty)
            if let first = hits.first {
                OpenWithMenu(model: model, hits: hits, url: URL(fileURLWithPath: first.path))
            } else {
                Menu(L("action.openWith")) {}.disabled(true)
            }
            Divider()
            Button(L("action.getInfo")) { model.getInfo(hits) }
                .keyboardShortcut("i")
                .disabled(hits.isEmpty)
            Button(L("action.rename")) { if let h = hits.first { model.renamePrompt(h, undo: undo) } }
                .disabled(hits.count != 1)
            Button(L("action.quickLook")) { model.quickLook(hits) }
                .keyboardShortcut("y")
                .disabled(hits.isEmpty)
            Divider()
            Button(L("action.reveal")) { model.reveal(hits) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(hits.isEmpty)
            Button(L("action.copy")) { model.copyPaths(hits) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(hits.isEmpty)
            Divider()
            Button(L("action.trash")) {
                // In a text field, ⌘⌫ deletes to the start of the line, as everywhere.
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                } else if model.reviewIndex == nil && !model.showDupes {
                    model.trash(hits, undo: undo)
                }
            }
            .keyboardShortcut(.delete)
            .disabled(hits.isEmpty)
            Divider()
            Button(L("menu.indexFolder")) { model.chooseFolderToIndex() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
        // Laserdot+'s own recent documents stay empty (privacy).
        NSDocumentController.shared.clearRecentDocuments(nil)
        NSApp.setActivationPolicy(.regular)
        model.start()
        drives.start()
        NotificationCenter.default.addObserver(forName: .updateProgress, object: nil, queue: .main) { [weak self] n in
            self?.model.notice = n.object as? String
        }
        Updates.shared.startChecking()
        if SelfTest.outDir == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { WhatsNew.showIfUpdated() }
        }
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
        NSDocumentController.shared.clearRecentDocuments(nil)
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
