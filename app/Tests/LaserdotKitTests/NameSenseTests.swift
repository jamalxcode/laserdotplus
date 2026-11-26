@testable import LaserdotKit
import XCTest

final class NameSenseTests: XCTestCase {
    func testUnclearNames() {
        for n in ["IMG_1234.jpg", "VID_20240812_183011.mp4", "DSC00042.JPG", "untitled 3.pdf", "PXL_20230101_120000.jpg",
                  "8f14e45fceea167a5a36dedd4bea2543.mov", "20230814_101500.jpg", "Screenshot 2024-01-05 at 10.11.12.png",
                  "GOPR0042.MP4", "Copy of IMG_9.png"] {
            XCTAssertTrue(NameSense.isUnclear(n), n)
        }
        for n in ["rome trip.txt", "IMG_1234 Rome beach.jpg", "invoice-march.pdf", "Wedding speech.mp4", "beach trip.jpg"] {
            XCTAssertFalse(NameSense.isUnclear(n), n)
        }
    }

    func testSuggestedNames() {
        let rows = ["photo.taken": "2023-08-14 15:04", "photo.camera": "Apple iPhone 12 Pro", "video.resolution": "1920 × 1080",
                    "general.duration": "0:42"]
        XCTAssertEqual(NameSense.suggest(name: "VID_0001.mp4", modified: 0, kind: "video", rows: rows),
                       "2023-08-14 Apple iPhone 12 Pro 1080p 0m42s.mp4")
        XCTAssertEqual(NameSense.suggest(name: "IMG_1.jpg", modified: 0, kind: "image", rows: ["photo.camera": "Canon/EOS"]),
                       "Canon-EOS.jpg")
    }
}
