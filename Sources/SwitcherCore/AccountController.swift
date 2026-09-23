import Foundation

private enum UsageRefreshResult: Sendable {
    case success(UUID, AccountUsage)
    case failure(UUID, String, authenticationRejected: Bool)
}

@MainActor
open class AccountController {
    public var onChange: (@MainActor () -> Void)?
    public private(set) var accounts: [AccountProfile] = [] { didSet { onChange?() } }
    public private(set) var activeAccountID: UUID? { didSet { onChange?() } }
    public private(set) var usageStates: [UUID: UsageViewState] = [:] { didSet { onChange?() } }
    public private(set) var balances: [UUID: AccountBalances] = [:] { didSet { onChange?() } }
    private var cachedBalanceIDs: Set<UUID> = [] { didSet { onChange?() } }
    public private(set) var settings: AppSettings = .default { didSet { onChange?() } }
    public private(set) var isMutating = false { didSet { onChange?() } }
    public private(set) var isAddingAccount = false { didSet { onChange?() } }
    public var visibleError: OperationError? { didSet { onChange?() } }
    public private(set) var activeIdentityConfirmed = true { didSet { onChange?() } }

    private let store: AccountStore
    private let codex: any AccountClient
    private let switchService: any SwitchServicing
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false

    public init(
        store: AccountStore,
        codex: any AccountClient,
        switchService: any SwitchServicing
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
    }

    public func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    public func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    public var activeRemainingPercent: Int? {
        guard let activeAccountID else { return nil }
        return usageStates[activeAccountID]?.displayedUsage?.remainingPercent
    }

    public func balanceLines(for id: UUID) -> [String] {
        guard let balance = balances[id] else { return [] }
        let lines = balance.lines(language: settings.language)
        guard cachedBalanceIDs.contains(id) else { return lines }
        let statusKey: String
        switch usageStates[id] {
        case .stale?, .unavailable?: statusKey = "cached_balances_refresh_failed"
        default: statusKey = "cached_balances"
        }
        return [text(statusKey)] + lines
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            settings = try await store.loadSettings()
            var registry = try await store.loadRegistry()
            if registry.accounts.isEmpty, await store.activeCredentialExists() {
                let activeHome = await store.activeCodexHome()
                let identity = try await codex.readIdentity(profileHome: activeHome)
                let profile = AccountProfile(
                    id: UUID(),
                    displayName: identity.suggestedDisplayName,
                    email: identity.email,
                    accountID: identity.accountID,
                    createdAt: Date(),
                    lastUsedAt: Date(),
                    planType: identity.planType
                )
                try await store.importCurrentProfile(profile)
                registry = try await store.loadRegistry()
            }
            apply(registry)
            do {
                apply(try await store.loadUsageCache())
            } catch {
                showError(error)
            }
            await confirmActiveIdentity()
        } catch {
            showError(error)
        }
    }

    public func refreshWeeklyUsage() {
        if isBackgroundUsageRefreshEnabled {
            scheduleNextWeeklyUsageRefresh()
        }
        guard !accounts.isEmpty, usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
        }
    }

    public func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    public func startBackgroundUsageRefresh(every interval: Duration = .seconds(300)) async {
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        await start()
        refreshWeeklyUsage()
    }

    public func stopBackgroundUsageRefresh() {
        isBackgroundUsageRefreshEnabled = false
        nextUsageRefreshTask?.cancel()
        nextUsageRefreshTask = nil
    }

    private func scheduleNextWeeklyUsageRefresh() {
        nextUsageRefreshTask?.cancel()
        let interval = backgroundUsageRefreshInterval
        nextUsageRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.nextUsageRefreshTask = nil
            self.refreshWeeklyUsage()
        }
    }

    private func performWeeklyUsageRefresh() async {
        let targets = await withTaskGroup(of: (UUID, URL).self, returning: [(UUID, URL)].self) { group in
            for account in accounts {
                group.addTask { [store] in
                    (account.id, await store.profileHome(id: account.id))
                }
            }
            var values: [(UUID, URL)] = []
            for await value in group { values.append(value) }
            return values
        }

        await withTaskGroup(of: UsageRefreshResult.self) { group in
            for (id, home) in targets {
                group.addTask { [codex] in
                    do {
                        return .success(id, try await codex.readAccountUsage(profileHome: home))
                    } catch {
                        return .failure(id, error.localizedDescription,
                            authenticationRejected: (error as? CodexClientError)?.isAuthenticationRejected == true)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .success(id, usage):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    usageStates[id] = usage.weekly.map(UsageViewState.loaded)
                        ?? .unavailable(text("weekly_usage_not_provided"))
                    balances[id] = usage.balances
                    cachedBalanceIDs.remove(id)
                    do {
                        try await store.cacheAccountUsage(usage, profileID: id)
                    } catch {
                        showError(error)
                    }
                case let .failure(id, message, authenticationRejected):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    if balances[id] != nil { cachedBalanceIDs.insert(id) }
                    let visibleMessage = authenticationRejected ? text("usage_auth_rejected") : message
                    if let cached = usageStates[id]?.displayedUsage {
                        usageStates[id] = .stale(cached, visibleMessage)
                    } else {
                        usageStates[id] = .unavailable(visibleMessage)
                    }
                }
            }
        }
    }

    public func switchAccount(to id: UUID) async {
        guard id != activeAccountID, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await switchService.switchAccount(to: id)
            apply(try await store.loadRegistry())
            activeIdentityConfirmed = true
        } catch let error as OperationError {
            if error.stage == .reopenDesktop {
                do {
                    apply(try await store.loadRegistry())
                    activeIdentityConfirmed = true
                } catch {
                    showError(error)
                    return
                }
                visibleError = OperationError(
                    stage: .reopenDesktop,
                    titleKey: "switched_reopen_title",
                    messageKey: "switched_reopen_message",
                    message: text("switched_reopen_message"),
                    underlyingDescription: error.underlyingDescription
                )
            } else {
                if error.stage == .saveCurrentCredential { activeIdentityConfirmed = false }
                visibleError = error
            }
        } catch {
            showError(error)
        }
    }

    public func addAccount() {
        guard !isMutating, !isAddingAccount else { return }
        isAddingAccount = true
        addAccountTask = Task { [weak self] in
            guard let self else { return }
            await self.performAddAccount()
            self.isAddingAccount = false
            self.addAccountTask = nil
        }
    }

    public func cancelAddingAccount() {
        addAccountTask?.cancel()
    }

    private func performAddAccount() async {
        let id = UUID()
        do {
            let home = try await store.createProfileDirectory(id: id)
            try Task.checkCancellation()
            let identity = try await codex.login(profileHome: home)
            try Task.checkCancellation()
            let profile = AccountProfile(
                id: id,
                displayName: identity.suggestedDisplayName,
                email: identity.email,
                accountID: identity.accountID,
                createdAt: Date(),
                lastUsedAt: nil,
                planType: identity.planType
            )
            try await store.addProfile(profile)
            apply(try await store.loadRegistry())
            await waitForWeeklyUsageRefresh()
            refreshWeeklyUsage()
        } catch {
            let loginError = error
            do {
                try await store.discardUnregisteredProfile(id: id)
            } catch {
                showError(NSError(domain: "CodexAccountSwitcher.Login", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(loginError.localizedDescription) Removing the incomplete profile also failed: \(error.localizedDescription)",
                ]))
                return
            }
            if !(loginError is CancellationError) { showError(loginError) }
        }
    }

    public func registerCurrentAccount() async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            try await store.registerActiveIdentity(identity)
            apply(try await store.loadRegistry())
            activeIdentityConfirmed = true
            visibleError = nil
            await waitForWeeklyUsageRefresh()
            refreshWeeklyUsage()
        } catch { showError(error) }
    }

    public func removeAccount(id: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await store.removeAccount(id: id)
            apply(try await store.loadRegistry())
            usageStates[id] = nil
            balances[id] = nil
        } catch {
            showError(error)
        }
    }

    public func setLanguage(_ language: AppLanguage) async {
        settings.language = language
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func setShowsMenuBarPercentage(_ enabled: Bool) async {
        settings.showsMenuBarPercentage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func setShowsFiveHourUsage(_ enabled: Bool) async {
        settings.showsFiveHourUsage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func dismissError() {
        visibleError = nil
    }

    private func apply(_ registry: AccountRegistry) {
        accounts = registry.accounts
        activeAccountID = registry.activeAccountID
        usageStates = usageStates.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        balances = balances.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        cachedBalanceIDs.formIntersection(registry.accounts.map(\.id))
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            if let usage = entry.usage { usageStates[entry.profileID] = .loaded(usage) }
            balances[entry.profileID] = entry.balances
            if entry.balances != nil { cachedBalanceIDs.insert(entry.profileID) }
        }
    }

    private func confirmActiveIdentity() async {
        guard await store.activeCredentialExists() else {
            activeIdentityConfirmed = activeAccountID == nil
            return
        }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            if let activeID = activeAccountID,
               let profile = accounts.first(where: { $0.id == activeID }),
               identity.matches(profile) {
                activeIdentityConfirmed = true
                return
            }
            let matches = accounts.filter { identity.matches($0) }
            guard matches.count == 1 else {
                activeIdentityConfirmed = false
                return
            }
            try await store.commitActiveAccountID(matches[0].id)
            apply(try await store.loadRegistry())
            activeIdentityConfirmed = true
        } catch {
            activeIdentityConfirmed = false
        }
    }

    private func showError(_ error: any Error) {
        visibleError = OperationError(
            stage: nil,
            titleKey: "operation_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }
}
