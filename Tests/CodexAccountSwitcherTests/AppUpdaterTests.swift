@testable import SwitcherCore
import Foundation
import Sparkle
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct AppUpdaterTests {
    @Test func forkUpdatesOpenTheirOwnReleasePageWithoutStartingSparkle() {
        let page = URL(string: "https://github.com/Herbertmt978/codex-account-switcher/releases/latest")!
        var opened: [URL] = []
        let adapter = AppUpdater(releasePage: page, openReleasePage: { opened.append($0) })
        adapter.start()
        #expect(adapter.canCheckForUpdates)
        #expect(!adapter.supportsAutomaticChecks)
        adapter.setAutomaticallyChecks(true)
        #expect(!adapter.automaticallyChecks)
        adapter.accountOperationInProgress = true
        adapter.checkForUpdates()
        #expect(opened.isEmpty)
        adapter.accountOperationInProgress = false
        adapter.checkForUpdates()
        #expect(opened == [page])
        #expect(!adapter.isInstalling)
    }

    @Test func successfulBackgroundCheckClearsPreviousNetworkError() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info: [String: String] = [
            "CFBundleIdentifier": "com.liuzhao.switcher-updater-tests",
            "CFBundleVersion": "7", "CFBundleName": "Updater tests",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let engine = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        let adapter = AppUpdater()

        adapter.updater(engine, didAbortWithError: URLError(.notConnectedToInternet))
        #expect(adapter.lastError != nil)
        adapter.updater(engine, didAbortWithError: NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)
        ))
        #expect(adapter.lastError == nil)
        adapter.updater(engine, didAbortWithError: URLError(.timedOut))
        #expect(adapter.lastError != nil)
    }
}
