import XCTest
@testable import RunningPageSyncCore

final class ZipArchiveTests: XCTestCase {
    func testBuildsStoredZipArchiveWithMultipleGPXFiles() throws {
        let archive = try ZipArchiveBuilder().archive(entries: [
            ZipEntry(name: "first.gpx", data: Data("first".utf8)),
            ZipEntry(name: "second.gpx", data: Data("second".utf8))
        ])

        XCTAssertEqual(Array(archive.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertTrue(archive.range(of: Data("first.gpx".utf8)) != nil)
        XCTAssertTrue(archive.range(of: Data("second.gpx".utf8)) != nil)
        XCTAssertTrue(archive.range(of: Data("first".utf8)) != nil)
        XCTAssertEqual(Array(archive.suffix(22).prefix(4)), [0x50, 0x4b, 0x05, 0x06])
    }

    func testArchiveIsReadableByStandardZipImplementation() throws {
        let archive = try ZipArchiveBuilder().archive(entries: [
            ZipEntry(name: "route.gpx", data: Data("<gpx>route</gpx>".utf8))
        ])
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("running-page-sync-\(UUID().uuidString).zip")
        try archive.write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-c",
            "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); assert z.read('route.gpx') == b'<gpx>route</gpx>'",
            archiveURL.path
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testRejectsUnsafeOrNonGPXEntryNames() {
        for name in ["../route.gpx", "/route.gpx", "route.txt", "folder//route.gpx"] {
            XCTAssertThrowsError(
                try ZipArchiveBuilder().archive(entries: [
                    ZipEntry(name: name, data: Data())
                ])
            ) { error in
                XCTAssertEqual(error as? WorkoutSyncError, .invalidArchiveEntry)
            }
        }
    }
}
