import Testing
@testable import SwitcherCore

struct CodexClientErrorTests {
    @Test func identifiesRevokedAuthenticationWithoutTreatingOtherRemoteErrorsAsSignInFailures() {
        let revoked = CodexClientError.remoteError(code: -32603,
            message: "401 Unauthorized; body contains token_revoked: invalidated auth token")
        let other = CodexClientError.remoteError(code: -32603, message: "The usage service is temporarily unavailable.")

        #expect(revoked.isAuthenticationRejected)
        #expect(!other.isAuthenticationRejected)
        #expect(!CodexClientError.connectionClosed.isAuthenticationRejected)
    }
}
