import Foundation

// The same ordered handoff and bounded restoration run on both platforms.

public protocol DesktopControlling: Sendable {
    func closeDesktop() async throws
    func reopenDesktop() async throws
}

public protocol CodexIdentityReading: Sendable {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity
}

public protocol SwitchServicing: Sendable {
    func switchAccount(to targetID: UUID) async throws
}

public struct SwitchService: SwitchServicing {
    public let desktop: any DesktopControlling
    public let store: any AccountStoring
    public let codex: any CodexIdentityReading

    public init(desktop: any DesktopControlling, store: any AccountStoring, codex: any CodexIdentityReading) {
        self.desktop = desktop; self.store = store; self.codex = codex
    }

    public func switchAccount(to targetID: UUID) async throws {
        let target: AccountProfile
        let originalActiveID: UUID?
        let originalProfile: AccountProfile?
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            let registry = try await store.loadRegistry()
            originalActiveID = registry.activeAccountID
            if let activeID = registry.activeAccountID {
                guard let profile = registry.accounts.first(where: { $0.id == activeID }) else {
                    throw AccountStoreError.activeProfileMissing
                }
                originalProfile = profile
            } else {
                guard await !store.activeCredentialExists() else {
                    throw AccountStoreError.activeProfileMissing
                }
                originalProfile = nil
            }
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        // Reject stale or mismatched logins before touching Desktop. Recheck the
        // active credential after it exits in case Desktop writes it on shutdown.
        if let originalProfile {
            do {
                let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
                guard identity.matches(originalProfile) else {
                    throw AccountStoreError.activeCredentialMismatch
                }
            } catch {
                throw OperationError(
                    stage: .saveCurrentCredential,
                    titleKey: "switch_failed",
                    messageKey: "active_unconfirmed",
                    message: L10n.string("active_unconfirmed", language: .english),
                    underlyingDescription: String(describing: error)
                )
            }
        }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.profileHome(id: targetID))
            guard identity.matches(target) else { throw CodexClientError.identityUnavailable }
        } catch {
            throw targetIdentityFailure(error, restored: false)
        }

        do {
            try await desktop.closeDesktop()
        } catch {
            throw OperationError.stage(.closeDesktop, error)
        }

        do {
            if let originalProfile {
                let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
                guard identity.matches(originalProfile) else {
                    throw AccountStoreError.activeCredentialMismatch
                }
                try await store.saveCurrentCredential()
            } else if await store.activeCredentialExists() {
                throw AccountStoreError.activeCredentialMismatch
            }
        } catch {
            throw await reopeningOriginalDesktop(after: .stage(.saveCurrentCredential, error))
        }

        do {
            try await store.activateTargetCredential(id: targetID)
        } catch {
            throw await reopeningOriginalDesktop(after: .stage(.activateTargetCredential, error))
        }

        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
        } catch {
            throw await restoringOriginalCredential(
                originalActiveID: originalActiveID,
                failedStage: .verifyTargetIdentity,
                originalError: error
            )
        }

        do {
            try await store.commitActiveAccountID(targetID)
        } catch {
            throw await restoringOriginalCredential(
                originalActiveID: originalActiveID,
                failedStage: .commitActiveAccountID,
                originalError: error
            )
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func restoringOriginalCredential(
        originalActiveID: UUID?,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        do {
            if let originalActiveID {
                try await store.restoreActiveCredential(id: originalActiveID)
            } else {
                try await store.clearActiveCredential()
            }
            let failure = failedStage == .verifyTargetIdentity
                ? targetIdentityFailure(originalError, restored: true) : OperationError.stage(failedStage, originalError)
            return await reopeningOriginalDesktop(after: failure)
        } catch let restorationError {
            return OperationError(
                stage: failedStage,
                titleKey: "switch_failed",
                messageKey: nil,
                message: """
                \(originalError.localizedDescription) Restoring the previous credential also failed: \
                \(restorationError.localizedDescription)
                """,
                underlyingDescription: """
                \(String(describing: originalError)); restoration: \
                \(String(describing: restorationError))
                """
            )
        }
    }

    private func targetIdentityFailure(_ error: any Error, restored: Bool) -> OperationError {
        let key = restored ? "target_sign_in_unverified" : "target_sign_in_preflight_failed"
        return OperationError(
            stage: .verifyTargetIdentity,
            titleKey: "switch_failed",
            messageKey: key,
            message: L10n.string(key, language: .english),
            underlyingDescription: String(describing: error)
        )
    }

    private func reopeningOriginalDesktop(after failure: OperationError) async -> OperationError {
        do {
            try await desktop.reopenDesktop()
            return failure
        } catch {
            return OperationError(
                stage: failure.stage,
                titleKey: failure.titleKey,
                messageKey: nil,
                message: "\(failure.message) Reopening Codex Desktop also failed: \(error.localizedDescription)",
                underlyingDescription: "\(failure.underlyingDescription ?? failure.message); reopening: \(error)"
            )
        }
    }
}
