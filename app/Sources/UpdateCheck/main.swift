import Foundation

// laserdotplus-update-check: the only Laserdot+ code that uses the network
// (the owner asked for "a check for updates"). It asks GitHub one thing —
// which Laserdot+ release is the latest — and prints its version ("0.1.2").
// It sends nothing about the user or their files: one request to github.com,
// in an ephemeral session (no cookies, no cache on disk). The app runs it
// only when asked (Check for Updates…, or once a day if turned on); the app
// and the engine themselves have no network code (CI checks).

let latest = URL(string: "https://github.com/jamalxcode/laserdotplus/releases/latest")!

let config = URLSessionConfiguration.ephemeral
config.httpCookieStorage = nil
config.httpShouldSetCookies = false
config.urlCache = nil
config.requestCachePolicy = .reloadIgnoringLocalCacheData
config.timeoutIntervalForRequest = 15
config.httpAdditionalHeaders = ["User-Agent": "Laserdot+"]

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

let delegate = NoRedirect()
let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
var request = URLRequest(url: latest)
request.httpMethod = "HEAD"
let done = DispatchSemaphore(value: 0)
var failure: String?
session.dataTask(with: request) { _, response, error in
    if let error { failure = error.localizedDescription }
    if delegate.location == nil, let http = response as? HTTPURLResponse {
        delegate.location = http.value(forHTTPHeaderField: "Location")
    }
    done.signal()
}.resume()
_ = done.wait(timeout: .now() + 20)

guard let loc = delegate.location, let tag = loc.split(separator: "/").last, tag.hasPrefix("v") else {
    FileHandle.standardError.write(Data("no answer from GitHub: \(failure ?? "no release found")\n".utf8))
    exit(1)
}
print(tag.dropFirst())
