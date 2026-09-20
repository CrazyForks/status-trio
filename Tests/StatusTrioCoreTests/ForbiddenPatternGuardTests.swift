import Foundation
import XCTest

/// Runs the AGENTS.md forbidden-pattern guard as part of `swift test`.
///
/// This is the enforcement point, deliberately not a workflow step: every CI
/// job and every local run that executes the suite runs the guard, and the
/// workflow files stay owned by their own plans.
final class ForbiddenPatternGuardTests: XCTestCase {
    /// The guard's success contract, verbatim from
    /// `scripts/check-forbidden-patterns.sh`: the clean run writes this line to
    /// stdout and exits 0. There is no `forbidden-patterns: clean` line — a
    /// violation run writes its block to stderr instead and exits 1.
    private static let cleanOutput = "No forbidden actor-isolated method references found"

    func testSourcesContainNoActorIsolatedMethodReferences() throws {
        let result = try runGuardScript(arguments: [])
        XCTAssertEqual(
            result.status,
            0,
            "scripts/check-forbidden-patterns.sh reported violations:\n\(result.output)"
        )
        XCTAssertTrue(
            result.output.contains(Self.cleanOutput),
            """
            scripts/check-forbidden-patterns.sh exited 0 without printing its \
            clean-run confirmation (\(Self.cleanOutput)); the guard's output \
            contract changed:
            \(result.output)
            """
        )
    }

    func testGuardSelfTestPasses() throws {
        let result = try runGuardScript(arguments: ["--self-test"])
        XCTAssertEqual(
            result.status,
            0,
            "the guard's own precision self-test failed:\n\(result.output)"
        )
    }

    /// `<package root>/Tests/StatusTrioCoreTests/<this file>`.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The failure raised when the guard script is not where the repository
    /// keeps it.
    ///
    /// This is a hard failure, deliberately not an `XCTSkip`: a skip would turn
    /// deleting or renaming `scripts/check-forbidden-patterns.sh` into a green
    /// run, silently retiring the AGENTS.md rule this file enforces (the shape
    /// that crashed the compiler in CI run `34758026894`). The script is
    /// committed in this repository and `swift test` always runs from the
    /// package source, so there is no legitimate checkout in which it is absent.
    private struct GuardScriptUnavailable: Error, CustomStringConvertible, LocalizedError {
        /// The path derived from `#filePath` that the test looked for.
        let expectedPath: String

        var description: String {
            """
            the forbidden-pattern guard script is missing or unreadable: \
            \(expectedPath)
            scripts/check-forbidden-patterns.sh is committed in this repository: \
            it is the enforcement point for the AGENTS.md rule that an \
            actor-isolated method must never be passed directly as a function \
            value. A checkout without it is broken, so this test fails closed \
            instead of skipping. Restore the script, or fix the package-root \
            derivation in this file if the repository layout moved.
            """
        }

        var errorDescription: String? { description }
    }

    /// Runs the guard with stdout and stderr merged, so a violation block
    /// written to stderr is visible in the failure message.
    private func runGuardScript(arguments: [String]) throws -> (status: Int32, output: String) {
        let script = packageRoot.appendingPathComponent("scripts/check-forbidden-patterns.sh")
        // Fail closed. Throwing from a `throws` test is itself an XCTest failure,
        // and it prints the error's `description` verbatim, so the missing-script
        // message names the expected path instead of reporting a bare skip.
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw GuardScriptUnavailable(expectedPath: script.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = packageRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting: a full pipe would deadlock waitUntilExit().
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
