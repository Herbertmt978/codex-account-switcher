import Foundation
#if os(Windows)
import SwitcherPlatform
#endif

/// Reads identity metadata only. Tokens stay in the credential file and never enter snapshots.
enum CredentialIdentity {
    static func read(from home: URL) throws -> AccountIdentity? {
        let url = home.appending(path: "auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            #if os(Windows)
            guard switcher_check_path(url.path) == 0 else { throw CodexClientError.identityUnavailable }
            #endif
            return try decode(Data(contentsOf: url))
        } catch {
            // Decoder diagnostics can include credential contents.
            throw CodexClientError.identityUnavailable
        }
    }

    static func decode(_ data: Data) throws -> AccountIdentity? {
        let credential = try JSONDecoder().decode(Credential.self, from: data)
        guard let tokens = credential.tokens else { return nil }
        let claims = tokens.id_token.flatMap(decodeClaims)
        let accountID = nonempty(tokens.account_id) ?? nonempty(claims?.auth?.chatgpt_account_id)
        guard let accountID else { return nil }
        return AccountIdentity(accountID: accountID, email: nonempty(claims?.email),
                               planType: nonempty(claims?.auth?.chatgpt_plan_type))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func decodeClaims(_ token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        // These claims label a locally stored login; Codex still authenticates with the service.
        return try? JSONDecoder().decode(Claims.self, from: data)
    }

    private struct Credential: Decodable {
        let tokens: Tokens?
    }
    private struct Tokens: Decodable {
        let account_id: String?
        let id_token: String?
    }
    private struct Claims: Decodable {
        let email: String?
        let auth: Auth?
        enum CodingKeys: String, CodingKey {
            case email
            case auth = "https://api.openai.com/auth"
        }
    }
    private struct Auth: Decodable {
        let chatgpt_account_id: String?
        let chatgpt_plan_type: String?
    }
}
