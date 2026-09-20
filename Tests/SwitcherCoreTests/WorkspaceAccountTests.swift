import Foundation
import Testing
@testable import SwitcherCore

struct WorkspaceAccountTests {
    private func profile(_ account: String?, email: String = "person@example.test") -> AccountProfile {
        AccountProfile(id: UUID(), displayName: "Person", email: email, accountID: account, createdAt: Date())
    }

    @Test func sameEmailDoesNotMergeDifferentWorkspaces() {
        let identity = AccountIdentity(accountID: "personal", email: "person@example.test")
        #expect(!identity.matches(profile("workspace")))
        #expect(!identity.matches(profile(nil)))
        #expect(!AccountIdentity(accountID: nil, email: "person@example.test").matches(profile("personal")))
        #expect(identity.matches(profile("personal", email: "PERSON@example.test")))
        #expect(!identity.matches(profile("personal", email: "someone-else@example.test")))
    }

    @Test func credentialMetadataIdentifiesTheSelectedAccount() throws {
        let identity = try #require(try CredentialIdentity.decode(credential("workspace", plan: "business")))
        #expect(identity.accountID == "workspace")
        #expect(identity.email == "person@example.test")
        #expect(identity.planType == "business")
    }

    @Test func tokenAccountIDTakesPrecedenceOverClaims() throws {
        var value = try #require(JSONSerialization.jsonObject(with: credential("personal")) as? [String: Any])
        var tokens = try #require(value["tokens"] as? [String: Any])
        tokens["account_id"] = "selected-workspace"
        value["tokens"] = tokens
        #expect(try CredentialIdentity.decode(JSONSerialization.data(withJSONObject: value))?.accountID == "selected-workspace")
    }

    @Test func legacyProfilesRecoverTheirOwnIdentityWithoutChangingCredentialsOrCache() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.clean() }
        let old = profile(nil)
        try credential("workspace", plan: "business").write(to: fixture.active.appending(path: "auth.json"))
        try await fixture.store.importCurrentProfile(old)
        let usage = WeeklyUsage(remainingPercent: 72, resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
        try await fixture.store.cacheWeeklyUsage(usage, profileID: old.id)
        try credential("personal").write(to: fixture.active.appending(path: "auth.json"))
        let fresh = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        let upgraded = try await fresh.loadRegistry()
        #expect(upgraded.accounts.count == 1)
        #expect(upgraded.accounts[0].id == old.id)
        #expect(upgraded.accounts[0].accountID == "workspace")
        #expect(upgraded.accounts[0].planType == "business")
        #expect(upgraded.activeAccountID == old.id)
        #expect(try await fresh.loadUsageCache().entries.first?.usage == usage)
        let home = await fresh.profileHome(id: old.id)
        #expect(try Data(contentsOf: home.appending(path: "auth.json")) == credential("workspace", plan: "business"))
        #expect(try Data(contentsOf: fixture.active.appending(path: "auth.json")) == credential("personal"))
        let reloaded = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        #expect(try await reloaded.loadRegistry() == upgraded)
    }

    @Test func twoContextsSwitchBothWaysAndRejectOnlyTheActualDuplicate() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.clean() }
        let personal = profile("personal")
        let workspace = profile("workspace")
        try credential("personal").write(to: fixture.active.appending(path: "auth.json"))
        try await fixture.store.importCurrentProfile(personal)
        let workHome = try await fixture.store.createProfileDirectory(id: workspace.id)
        try credential("workspace", plan: "business").write(to: workHome.appending(path: "auth.json"))
        try await fixture.store.addProfile(workspace)
        let duplicate = profile("workspace")
        let duplicateHome = try await fixture.store.createProfileDirectory(id: duplicate.id)
        try credential("workspace").write(to: duplicateHome.appending(path: "auth.json"))
        await #expect(throws: AccountStoreError.duplicateAccount) { try await fixture.store.addProfile(duplicate) }
        let service = SwitchService(desktop: WorkspaceDesktop(), store: fixture.store, codex: WorkspaceIdentityReader())
        try await service.switchAccount(to: workspace.id)
        #expect(try await fixture.store.loadRegistry().activeAccountID == workspace.id)
        #expect(try CredentialIdentity.read(from: fixture.active)?.accountID == "workspace")
        try await service.switchAccount(to: personal.id)
        #expect(try await fixture.store.loadRegistry().activeAccountID == personal.id)
        #expect(try CredentialIdentity.read(from: fixture.active)?.accountID == "personal")
        #expect(try await fixture.store.loadRegistry().accounts.count == 2)
    }

    @Test func wrongWorkspaceWithSameEmailStopsAndRestoresTheOriginalCredential() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.clean() }
        let personal = profile("personal")
        let workspace = profile("workspace")
        try credential("personal").write(to: fixture.active.appending(path: "auth.json"))
        try await fixture.store.importCurrentProfile(personal)
        let home = try await fixture.store.createProfileDirectory(id: workspace.id)
        try credential("wrong-workspace").write(to: home.appending(path: "auth.json"))
        try await fixture.store.addProfile(workspace)
        let service = SwitchService(desktop: WorkspaceDesktop(), store: fixture.store, codex: WorkspaceIdentityReader())
        do { try await service.switchAccount(to: workspace.id); Issue.record("Wrong workspace must fail") }
        catch { #expect((error as? OperationError)?.stage == .verifyTargetIdentity) }
        #expect(try CredentialIdentity.read(from: fixture.active)?.accountID == "personal")
        #expect(try await fixture.store.loadRegistry().activeAccountID == personal.id)
    }

    @Test func fullBrowserChooserPreservesOAuthSecurityParameters() throws {
        let url = try #require(URL(string: "https://auth.openai.com/oauth/authorize?state=fixture&code_challenge=a%2Bb&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&codex_cli_simplified_flow=true&id_token_add_organizations=true"))
        let selected = CodexClient.accountSelectionURL(url)
        let query = try #require(URLComponents(url: selected, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(values["state"] == "fixture")
        #expect(values["code_challenge"] == "a+b")
        #expect(values["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(values["id_token_add_organizations"] == "true")
        #expect(values["prompt"] == "select_account")
        #expect(values["codex_cli_simplified_flow"] == "false")
    }

    @MainActor @Test func balancesStaySeparateSurviveRestartAndAreMarkedCachedAfterFailure() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.clean() }
        let personal = profile("personal"), workspace = profile("workspace")
        try credential("personal").write(to: fixture.active.appending(path: "auth.json"))
        try await fixture.store.importCurrentProfile(personal)
        let home = try await fixture.store.createProfileDirectory(id: workspace.id)
        try credential("workspace").write(to: home.appending(path: "auth.json"))
        try await fixture.store.addProfile(workspace)
        let client = WorkspaceUsageClient()
        let service = SwitchService(desktop: WorkspaceDesktop(), store: fixture.store, codex: client)
        let model = AccountController(store: fixture.store, codex: client, switchService: service)
        await model.start()
        await model.setLanguage(.english)
        model.refreshWeeklyUsage(); await model.waitForWeeklyUsageRefresh()
        #expect(model.balances[personal.id]?.availableResets == 2)
        #expect(model.balances[workspace.id]?.availableResets == 0)
        #expect(model.balances[workspace.id]?.credits?.balance == "250")
        #expect(model.usageStates[workspace.id]?.displayedUsage == nil)
        #expect(!model.balanceLines(for: personal.id).contains("Cached balances — awaiting refresh"))
        await client.setFailure()
        model.refreshWeeklyUsage(); await model.waitForWeeklyUsageRefresh()
        #expect(model.balances[personal.id]?.availableResets == 2)
        #expect(model.balanceLines(for: workspace.id).first == "Cached balances — awaiting refresh")
        let newStore = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        let restarted = AccountController(store: newStore, codex: client, switchService: service)
        await restarted.start()
        #expect(restarted.balances[workspace.id]?.credits?.balance == "250")
        #expect(restarted.balanceLines(for: personal.id).first == "Cached balances — awaiting refresh")
    }
}

private struct WorkspaceFixture {
    let root: URL
    let base: URL
    let active: URL
    let store: AccountStore
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "workspace-fixture-\(UUID())")
        base = root.appending(path: "store"); active = root.appending(path: "active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: base, activeHomeURL: active)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private struct WorkspaceDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}
private struct WorkspaceIdentityReader: CodexIdentityReading {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        try #require(try CredentialIdentity.read(from: profileHome))
    }
}

private actor WorkspaceUsageClient: AccountClient {
    var failure = false
    func setFailure() { failure = true }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        try #require(try CredentialIdentity.read(from: profileHome))
    }
    func login(profileHome: URL) async throws -> AccountIdentity { try await readIdentity(profileHome: profileHome) }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage { throw CodexClientError.weeklyUsageUnavailable }
    func readAccountUsage(profileHome: URL) async throws -> AccountUsage {
        if failure { throw CodexClientError.connectionClosed }
        let isWorkspace = try CredentialIdentity.read(from: profileHome)?.accountID == "workspace"
        return AccountUsage(weekly: isWorkspace ? nil : WeeklyUsage(remainingPercent: 42, resetsAt: Date()),
            balances: AccountBalances(credits: .init(hasCredits: true, unlimited: false, balance: isWorkspace ? "250" : "100"),
                availableResets: isWorkspace ? 0 : 2, resetCredits: nil))
    }
}

func credential(_ account: String, plan: String = "pro") throws -> Data {
    let claims: [String: Any] = ["email": "person@example.test",
        "https://api.openai.com/auth": ["chatgpt_account_id": account, "chatgpt_plan_type": plan]]
    let payload = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": account,
        "id_token": "fixture.\(payload).fixture"]], options: [.sortedKeys])
}
