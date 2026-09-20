import Foundation

public struct AccountUsage: Sendable {
    public let weekly: WeeklyUsage?
    public let balances: AccountBalances?

    public init(weekly: WeeklyUsage?, balances: AccountBalances? = nil) {
        self.weekly = weekly; self.balances = balances
    }
}

public struct AccountBalances: Codable, Equatable, Sendable {
    public struct Credits: Codable, Equatable, Sendable {
        public let hasCredits: Bool
        public let unlimited: Bool
        public let balance: String?
    }
    public struct ResetCredit: Codable, Equatable, Sendable {
        public let expiresAt: Date?
    }
    public let credits: Credits?
    public let availableResets: Int?
    public let resetCredits: [ResetCredit]?

    static func parse(_ response: JSONValue, bucket: JSONValue?) -> AccountBalances {
        let credits: Credits?
        if let value = bucket?["credits"], let hasCredits = value["hasCredits"]?.boolValue,
           let unlimited = value["unlimited"]?.boolValue {
            credits = Credits(hasCredits: hasCredits, unlimited: unlimited, balance: value["balance"]?.stringValue)
        } else { credits = nil }
        let summary = response["rateLimitResetCredits"]
        let count = summary?["availableCount"]?.intValue.flatMap { $0 >= 0 ? $0 : nil }
        let details: [ResetCredit]?
        if let rows = summary?["credits"]?.arrayValue {
            details = rows.compactMap { row in
                guard row["status"]?.stringValue == "available",
                      row["resetType"]?.stringValue == "codexRateLimits" else { return nil }
                if let timestamp = row["expiresAt"]?.doubleValue, timestamp.isFinite {
                    return ResetCredit(expiresAt: Date(timeIntervalSince1970: timestamp))
                }
                if case .null? = row["expiresAt"] { return ResetCredit(expiresAt: nil) }
                return nil
            }
        } else { details = nil }
        return AccountBalances(credits: credits, availableResets: count, resetCredits: details)
    }

    /// Shared presentation for both native clients; opaque credit IDs are deliberately omitted.
    public func lines(language: AppLanguage) -> [String] {
        func text(_ key: String) -> String { L10n.string(key, language: language) }
        let balance: String
        if let credits {
            if credits.unlimited { balance = text("unlimited_credits") }
            else if let raw = credits.balance,
                    let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) {
                let formatter = NumberFormatter()
                formatter.locale = language == .simplifiedChinese ? Locale(identifier: "zh_CN")
                    : (language == .english ? Locale(identifier: "en_GB") : .current)
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                formatter.roundingMode = .down
                balance = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? text("balance_unavailable")
            } else { balance = credits.hasCredits ? text("balance_unavailable") : "0" }
        } else { balance = text("balance_unavailable") }
        var result = ["\(text("credits_balance")): \(balance)",
                      "\(text("available_resets")): \(availableResets.map(String.init) ?? text("balance_unavailable"))"]
        guard let availableResets, availableResets > 0 else { return result }
        guard let resetCredits, !resetCredits.isEmpty else {
            result.append(text("reset_expiry_unavailable")); return result
        }
        let hasAllExpiries = resetCredits.count >= availableResets
        if let nextExpiry = resetCredits.compactMap(\.expiresAt).min() {
            let formatter = DateFormatter()
            formatter.locale = language == .simplifiedChinese ? Locale(identifier: "zh_CN")
                : (language == .english ? Locale(identifier: "en_GB") : .current)
            formatter.dateStyle = .medium; formatter.timeStyle = .short
            let label = text(hasAllExpiries ? "next_reset_expiry" : "next_known_reset_expiry")
            result.append("\(label): \(formatter.string(from: nextExpiry))")
        } else {
            result.append(text(hasAllExpiries ? "resets_no_expiry" : "reset_expiry_unavailable"))
        }
        return result
    }
}
