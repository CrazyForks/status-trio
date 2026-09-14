import Foundation
import XCTest
@testable import StatusTrioCore

final class SingleInstanceGuardTests: XCTestCase {
    func testLockFileNameIsScopedByBundleIdentifier() {
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "com.example.StatusTrio"),
            "com.example.StatusTrio.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "com.example/Status Trio"),
            "com.example_Status_Trio.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: nil),
            "com.lingsmbp.StatusTrio.preview.lock"
        )
        XCTAssertEqual(
            SingleInstanceGuard.lockFileName(for: "  "),
            "com.lingsmbp.StatusTrio.preview.lock"
        )
    }

    func testSecondGuardCannotAcquireUntilFirstIsReleased() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard(lockPath: lockPath)
        )
        withExtendedLifetime(first) {}
        XCTAssertNil(SingleInstanceGuard(lockPath: lockPath))

        first = nil
        let second = try XCTUnwrap(SingleInstanceGuard(lockPath: lockPath))
        withExtendedLifetime(second) {}
    }

    func testSubprocessCannotAcquireLockUntilOwnerReleasesIt() throws {
        let pythonPath = "/usr/bin/python3"
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: pythonPath),
            "python3 is unavailable for the cross-process flock test"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatusTrioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockPath = directory.appendingPathComponent("StatusTrio.lock").path

        var first: SingleInstanceGuard? = try XCTUnwrap(
            SingleInstanceGuard(lockPath: lockPath)
        )
        withExtendedLifetime(first) {}
        XCTAssertEqual(
            try runFlockHelper(pythonPath: pythonPath, lockPath: lockPath),
            3
        )

        first = nil
        XCTAssertEqual(
            try runFlockHelper(pythonPath: pythonPath, lockPath: lockPath),
            0
        )
    }

    private func runFlockHelper(pythonPath: String, lockPath: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c",
            """
            import fcntl
            import os
            import sys

            fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                os.close(fd)
                sys.exit(3)
            os.close(fd)
            sys.exit(0)
            """,
            lockPath
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(decoding: outputData, as: UTF8.self)

        XCTAssertEqual(process.terminationReason, .exit, outputText)
        XCTAssertTrue([0, 3].contains(process.terminationStatus), outputText)
        return process.terminationStatus
    }
}
