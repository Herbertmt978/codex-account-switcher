import Foundation
import Testing
@testable import SwitcherCore

@MainActor
struct AccountControllerTests {
    @Test func firstActivationInstallsAndCommitsTheSavedAccount() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Demo", email: "demo@example.test", accountID: "demo-account", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client)
        try await service.switchAccount(to: id)
        #expect(try await fixture.store.loadRegistry().activeAccountID == id)
        #expect(try String(contentsOf: fixture.active.appendingPathComponent("auth.json"), encoding: .utf8) == "saved-fixture")
    }

    @Test func failedFirstActivationRestoresTheUnsignedInState() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Other", email: "other@example.test", accountID: "other", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-other-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client)
        do { try await service.switchAccount(to: id); Issue.record("Identity mismatch should fail.") }
        catch { #expect((error as? OperationError)?.stage == .verifyTargetIdentity) }
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)
        #expect(await !fixture.store.activeCredentialExists())
        #expect(try String(contentsOf: home.appendingPathComponent("auth.json"), encoding: .utf8) == "saved-other-fixture")
    }

    @Test func firstActivationRechecksForCredentialsCreatedDuringDesktopExit() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Demo", email: "demo@example.test", accountID: "demo-account", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let active = fixture.active
        let desktop = CredentialCreatingDesktop(active: active)
        let service = SwitchService(desktop: desktop, store: fixture.store, codex: fixture.client)
        do { try await service.switchAccount(to: id); Issue.record("An unexpected active login should stop switching.") }
        catch { #expect((error as? OperationError)?.stage == .saveCurrentCredential) }
        #expect(try String(contentsOf: active.appendingPathComponent("auth.json"), encoding: .utf8) == "unexpected-fixture")
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)
    }

    @Test func startupImportsCurrentLoginOnce() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        await fixture.model.start()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.activeAccountID == fixture.model.accounts.first?.id)
        #expect(fixture.model.activeIdentityConfirmed)
    }

    @Test func emptyStartupDoesNotCreateAnAccount() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        #expect(fixture.model.accounts.isEmpty)
        #expect(fixture.model.visibleError == nil)
    }

    @Test func registerUsesExistingIdentityAndPreservesProfile() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let id = fixture.model.activeAccountID
        await fixture.model.registerCurrentAccount()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.activeAccountID == id)
    }

    @Test func startupSelectsTheUniqueSavedProfileMatchingAnExternalLogin() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        let matching = AccountProfile(id: UUID(), displayName: "Current", email: "demo@example.test",
            accountID: "demo-account", createdAt: Date())
        let selected = AccountProfile(id: UUID(), displayName: "Previously selected", email: "other@example.test",
            accountID: "other-account", createdAt: Date())
        for profile in [matching, selected] {
            let home = try await fixture.store.createProfileDirectory(id: profile.id)
            try Data("saved-\(profile.displayName)".utf8).write(to: home.appendingPathComponent("auth.json"))
            try await fixture.store.addProfile(profile)
        }
        try await fixture.store.commitActiveAccountID(selected.id)

        await fixture.model.start()

        #expect(fixture.model.activeAccountID == matching.id)
        #expect(fixture.model.activeIdentityConfirmed)
        #expect(try await fixture.store.loadRegistry().activeAccountID == matching.id)
        #expect(try String(contentsOf: fixture.active.appendingPathComponent("auth.json"), encoding: .utf8)
            == "fixture-secret-token")
        #expect(try String(contentsOf: await fixture.store.profileHome(id: matching.id).appendingPathComponent("auth.json"), encoding: .utf8)
            == "saved-Current")
    }

    @Test func startupLeavesAmbiguousSavedProfilesUntouched() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        let first = AccountProfile(id: UUID(), displayName: "First", email: "demo@example.test",
            accountID: "demo-account", createdAt: Date())
        let second = AccountProfile(id: UUID(), displayName: "Second", email: "demo@example.test",
            accountID: "demo-account", createdAt: Date())
        let prior = AccountProfile(id: UUID(), displayName: "Prior", email: "other@example.test",
            accountID: "other-account", createdAt: Date())
        let storeRoot = fixture.root.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let registry = AccountRegistry(activeAccountID: prior.id, accounts: [first, second, prior])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(registry).write(to: storeRoot.appendingPathComponent("accounts.json"))

        await fixture.model.start()

        #expect(fixture.model.activeAccountID == prior.id)
        #expect(!fixture.model.activeIdentityConfirmed)
        #expect(try await fixture.store.loadRegistry().activeAccountID == prior.id)
    }

    @Test func refreshKeepsLastGoodUsageWhenTheServerFails() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        let id = try #require(fixture.model.activeAccountID)
        #expect(fixture.model.usageStates[id]?.displayedUsage?.remainingPercent == 72)
        await fixture.client.failUsage()
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.usageStates[id]?.displayedUsage?.remainingPercent == 72)
        #expect(fixture.model.usageStates[id]?.refreshError != nil)
        #expect(try await fixture.store.loadUsageCache().entries.first?.usage?.remainingPercent == 72)
    }

    @Test func addingAWorkspaceRefreshesItEvenWhenAnotherRefreshIsRunning() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        await fixture.client.allowWorkspaceLogin()
        await fixture.client.blockNextUsageRead()
        fixture.model.refreshWeeklyUsage()
        for _ in 0..<100 {
            if await fixture.client.usageReadIsBlocked { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await fixture.client.usageReadIsBlocked)
        fixture.model.addAccount()
        for _ in 0..<100 {
            if fixture.model.accounts.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        await fixture.client.unblockUsageRead()
        for _ in 0..<100 where fixture.model.isAddingAccount {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!fixture.model.isAddingAccount)
        let workspace = try #require(fixture.model.accounts.first(where: { $0.accountID == "workspace" }))
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.usageStates[workspace.id]?.displayedUsage?.remainingPercent == 72)
        #expect(try await fixture.store.loadUsageCache().entries.contains(where: { $0.profileID == workspace.id }))
    }

    @Test func registeringTheCurrentAccountRefreshesItsUsage() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        try fixture.writeActiveCredential()
        await fixture.model.registerCurrentAccount()
        await fixture.model.waitForWeeklyUsageRefresh()
        let id = try #require(fixture.model.activeAccountID)
        #expect(fixture.model.usageStates[id]?.displayedUsage?.remainingPercent == 72)
    }

    @Test func settingsAreSavedImmediately() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        await fixture.model.setLanguage(.simplifiedChinese)
        await fixture.model.setShowsMenuBarPercentage(false)
        await fixture.model.setShowsFiveHourUsage(true)
        let saved = try await fixture.store.loadSettings()
        #expect(saved.language == .simplifiedChinese)
        #expect(!saved.showsMenuBarPercentage)
        #expect(saved.showsFiveHourUsage)
    }

    @Test func activeProfileCannotBeRemoved() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let id = try #require(fixture.model.activeAccountID)
        await fixture.model.removeAccount(id: id)
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.visibleError != nil)
    }

    @Test func snapshotContainsPresentationButNoCredentialContents() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let data = try JSONEncoder().encode(fixture.model.snapshot)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("fixture-secret-token"))
        #expect(json.contains("demo@example.test"))
    }
}

@MainActor
private struct ControllerFixture {
    let root: URL
    let active: URL
    let store: AccountStore
    let client: FixtureClient
    let model: AccountController
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-core-test-\(UUID())")
        active = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: active)
        client = FixtureClient()
        model = AccountController(store: store, codex: client,
            switchService: SwitchService(desktop: FixtureDesktop(), store: store, codex: client))
    }
    func writeActiveCredential() throws {
        try Data("fixture-secret-token".utf8).write(to: active.appendingPathComponent("auth.json"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private actor FixtureClient: AccountClient {
    private var usageFails = false
    private var allowsWorkspaceLogin = false
    private var blocksNextUsage = false
    private var usageGate: CheckedContinuation<Void, Never>?
    var usageReadIsBlocked: Bool { usageGate != nil }
    func allowWorkspaceLogin() { allowsWorkspaceLogin = true }
    func blockNextUsageRead() { blocksNextUsage = true }
    func unblockUsageRead() { usageGate?.resume(); usageGate = nil }
    func failUsage() { usageFails = true }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        AccountIdentity(accountID: "demo-account", email: "demo@example.test")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        if blocksNextUsage {
            blocksNextUsage = false
            await withCheckedContinuation { usageGate = $0 }
        }
        if usageFails { throw CodexClientError.connectionClosed }
        return WeeklyUsage(remainingPercent: 72, resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
    }
    func login(profileHome: URL) async throws -> AccountIdentity {
        if allowsWorkspaceLogin {
            try Data("workspace-fixture".utf8).write(to: profileHome.appendingPathComponent("auth.json"))
            return AccountIdentity(accountID: "workspace", email: "demo@example.test", planType: "team")
        }
        throw CodexClientError.loginFailed("Fixture login is disabled.")
    }
}

private struct FixtureDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}

private struct CredentialCreatingDesktop: DesktopControlling {
    let active: URL
    func closeDesktop() async throws {
        try Data("unexpected-fixture".utf8).write(to: active.appendingPathComponent("auth.json"))
    }
    func reopenDesktop() async throws {}
}
