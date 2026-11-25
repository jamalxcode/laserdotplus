import Foundation

// laserdotplus-update-check: the only Laserdot+ code that uses the network
// (the owner asked for "a check for updates", then for it to "self update,
// not send me to a downloads page"). It speaks to GitHub only, in an
// ephemeral session (no cookies, no cache on disk), and sends nothing about
// the user or their files. The app and the engine have no network code (CI
// checks).
//
//   laserdotplus-update-check
//       asks which release is the latest (one HEAD request) and prints its
//       version ("0.1.4").
//   laserdotplus-update-check --install 0.1.4 --app /Applications/Laserdot+.app --pid 123
//       downloads that release's disk image from GitHub, checks the app in it
//       (same bundle, that version), copies it next to the old one and prints
//       "ready"; then waits for the running Laserdot+ (pid) to quit, puts the
//       old copy in the Trash, moves the new one into its place and opens it.

signal(SIGPIPE, SIG_IGN) // the app stops reading once it has quit

let repo = "https://github.com/jamalxcode/laserdotplus"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func session(delegate: URLSessionTaskDelegate?) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 30
    config.httpAdditionalHeaders = ["User-Agent": "Laserdot+"]
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
}

/// Stops at the first redirect: its address names the latest release
/// (…/releases/tag/v0.1.2), so the release page itself is never downloaded.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    var location: String?
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        location = request.url?.absoluteString
        completionHandler(nil)
    }
}

/// A release file is served from GitHub's own file hosts: follow redirects
/// there and nowhere else.
final class GitHubOnly: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let host = request.url?.host ?? ""
        let ok = request.url?.scheme == "https" && (host == "github.com" || host.hasSuffix(".githubusercontent.com"))
        completionHandler(ok ? request : nil)
    }
}

func latestVersion() -> String {
    let delegate = NoRedirect()
    var request = URLRequest(url: URL(string: repo + "/releases/latest")!)
    request.httpMethod = "HEAD"
    let done = DispatchSemaphore(value: 0)
    var failure: String?
    session(delegate: delegate).dataTask(with: request) { _, response, error in
        if let error { failure = error.localizedDescription }
        if delegate.location == nil, let http = response as? HTTPURLResponse {
            delegate.location = http.value(forHTTPHeaderField: "Location")
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 20)
    guard let loc = delegate.location, let tag = loc.split(separator: "/").last, tag.hasPrefix("v") else {
        fail("no answer from GitHub: \(failure ?? "no release found")")
    }
    return String(tag.dropFirst())
}

@discardableResult
func run(_ tool: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

func info(_ app: URL, _ key: String) -> String? {
    NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?[key] as? String
}

func install(version: String, app: URL, pid: pid_t) -> Never {
    guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else { fail("bad version \(version)") }
    let fm = FileManager.default
    let work = fm.temporaryDirectory.appendingPathComponent("laserdotplus-update-\(UUID().uuidString)")
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }

    // 1. The release's disk image, from GitHub.
    let dmgURL = URL(string: "\(repo)/releases/download/v\(version)/LaserdotPlus-\(version).dmg")!
    let dmg = work.appendingPathComponent("update.dmg")
    let done = DispatchSemaphore(value: 0)
    var failure = "no answer from GitHub"
    session(delegate: GitHubOnly()).downloadTask(with: dmgURL) { file, response, error in
        if let file, (response as? HTTPURLResponse)?.statusCode == 200 {
            do { try fm.moveItem(at: file, to: dmg); failure = "" } catch { failure = error.localizedDescription }
        } else if let error {
            failure = error.localizedDescription
        } else {
            failure = "GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)"
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 600)
    guard failure.isEmpty else { fail("download failed: \(failure)") }

    // 2. The app inside it: the same app, that version.
    let mnt = work.appendingPathComponent("mnt")
    guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mnt.path, dmg.path]) == 0 else {
        fail("could not open the disk image")
    }
    let src = mnt.appendingPathComponent(app.lastPathComponent)
    let fresh = fm.fileExists(atPath: src.path) ? src : mnt.appendingPathComponent("Laserdot+.app")
    guard info(fresh, "CFBundleIdentifier") == info(app, "CFBundleIdentifier"),
          info(fresh, "CFBundleShortVersionString") == version else {
        run("/usr/bin/hdiutil", ["detach", "-force", mnt.path])
        fail("the disk image does not hold Laserdot+ \(version)")
    }

    // 3. Copied next to the old app (same disk, so the swap is one rename).
    let staged = app.deletingLastPathComponent().appendingPathComponent(".Laserdot+ \(version).app")
    try? fm.removeItem(at: staged)
    guard run("/usr/bin/ditto", [fresh.path, staged.path]) == 0 else {
        run("/usr/bin/hdiutil", ["detach", "-force", mnt.path])
        fail("could not copy the new version next to \(app.deletingLastPathComponent().path)")
    }
    run("/usr/bin/hdiutil", ["detach", "-force", mnt.path])
    print("ready")
    fflush(stdout)

    // 4. Once Laserdot+ has quit: the old copy to the Trash, the new one in.
    for _ in 0..<600 where kill(pid, 0) == 0 { usleep(100_000) }
    var trashed: NSURL?
    if (try? fm.trashItem(at: app, resultingItemURL: &trashed)) == nil {
        try? fm.moveItem(at: app, to: work.appendingPathComponent("old.app"))
    }
    do {
        try fm.moveItem(at: staged, to: app)
    } catch {
        if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: app) } // put the old one back
        fail("could not put the new version in place: \(error.localizedDescription)")
    }
    if ProcessInfo.processInfo.environment["LASERDOTPLUS_UPDATE_NO_OPEN"] == nil { // CI checks the swap only
        run("/usr/bin/open", [app.path])
    }
    exit(0)
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--install"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
        return args[j + 1]
    }
    guard let app = value("--app"), let pid = value("--pid").flatMap({ pid_t($0) }) else {
        fail("usage: --install VERSION --app PATH --pid PID")
    }
    install(version: args[i + 1], app: URL(fileURLWithPath: app), pid: pid)
}
print(latestVersion())
