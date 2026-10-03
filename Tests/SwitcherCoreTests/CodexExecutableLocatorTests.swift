import Foundation
import Testing
@testable import SwitcherCore

struct CodexExecutableLocatorTests {
    #if os(Windows)
    @Test func prefersInstalledCodexDesktopForDefaultLookup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runtime-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }

        let local = root.appendingPathComponent("local")
        let installed = local.appendingPathComponent("OpenAI/Codex/bin/current/codex.exe")
        let staging = local.appendingPathComponent("OpenAI/Codex/bin/.staging-current-incomplete/codex.exe")
        let pathCommand = root.appendingPathComponent("path/codex.exe")
        try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathCommand.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data().write(to: installed)
        try Data().write(to: pathCommand)
        // Make the incomplete staging directory newer without setting Windows folder timestamps.
        Thread.sleep(forTimeInterval: 0.05)
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data().write(to: staging)

        for override: String? in [nil, ""] {
            var environment = [
                "LOCALAPPDATA": local.path,
                "PATH": pathCommand.deletingLastPathComponent().path,
            ]
            if let override { environment["CODEX_CLI_PATH"] = override }
            #expect(try CodexExecutableLocator().locate(environment: environment) == installed)
        }
    }

    @Test func explicitCodexPathCommandsStillTakePrecedenceOverDesktop() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-override-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }

        let local = root.appendingPathComponent("local")
        let installed = local.appendingPathComponent("OpenAI/Codex/bin/current/codex.exe")
        let pathCommand = root.appendingPathComponent("path/codex.exe")
        try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathCommand.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data().write(to: installed)
        try Data().write(to: pathCommand)

        #expect(try CodexExecutableLocator().locate(environment: [
            "CODEX_CLI_PATH": "codex",
            "LOCALAPPDATA": local.path,
            "PATH": pathCommand.deletingLastPathComponent().path,
        ]) == pathCommand)

        #expect(throws: CodexClientError.executableNotFound) {
            _ = try CodexExecutableLocator().locate(environment: [
                "CODEX_CLI_PATH": "missing-codex",
                "LOCALAPPDATA": local.path,
                "PATH": pathCommand.deletingLastPathComponent().path,
            ])
        }
    }

    @Test func defaultLookupUsesPathWhenDesktopCliIsUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-path-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }

        let local = root.appendingPathComponent("local")
        let staging = local.appendingPathComponent("OpenAI/Codex/bin/.staging-current-incomplete/codex.exe")
        let pathCommand = root.appendingPathComponent("path/codex.exe")
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathCommand.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data().write(to: staging)
        try Data().write(to: pathCommand)

        for localPath in [root.appendingPathComponent("missing-local").path, local.path] {
            #expect(try CodexExecutableLocator().locate(environment: [
                "LOCALAPPDATA": localPath,
                "PATH": pathCommand.deletingLastPathComponent().path,
            ]) == pathCommand)
        }
    }
    #endif
}
