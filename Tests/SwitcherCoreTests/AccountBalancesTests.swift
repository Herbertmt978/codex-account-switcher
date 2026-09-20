import Foundation
import Testing
@testable import SwitcherCore

struct AccountBalancesTests {
    private func parse(_ json: String) throws -> AccountBalances {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return AccountBalances.parse(value, bucket: value["rateLimits"])
    }

    @Test func creditsAndResetExpiryAreIndependentOfWeeklyUsage() throws {
        let balance = try parse(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"125.50"}},"rateLimitResetCredits":{"availableCount":3,"credits":[{"status":"available","resetType":"codexRateLimits","expiresAt":2000000000},{"status":"available","resetType":"codexRateLimits","expiresAt":null}]}}"#)
        #expect(balance.credits?.balance == "125.50")
        #expect(balance.availableResets == 3)
        #expect(balance.resetCredits?.count == 2)
        #expect(balance.resetCredits?.first?.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(balance.lines(language: .english).count == 3)
        #expect(balance.lines(language: .english).last?.hasPrefix("Next known reset expiry: ") == true)
    }

    @Test func unknownDoesNotBecomeZeroOrNoExpiry() throws {
        let missing = try parse(#"{"rateLimits":{},"rateLimitResetCredits":null}"#)
        #expect(missing.credits == nil)
        #expect(missing.availableResets == nil)
        #expect(missing.lines(language: .english) == ["Credits: Unavailable", "Available resets: Unavailable"])
        let countOnly = try parse(#"{"rateLimitResetCredits":{"availableCount":4,"credits":null}}"#)
        #expect(countOnly.availableResets == 4)
        #expect(countOnly.resetCredits == nil)
        #expect(countOnly.lines(language: .english).last == "Reset expiry unavailable")
    }

    @Test func onlyTheEarliestExpiryIsShownWithTheFullAvailableCount() throws {
        let balance = try parse(#"{"rateLimitResetCredits":{"availableCount":4,"credits":[{"status":"available","resetType":"codexRateLimits","expiresAt":2100000000},{"status":"available","resetType":"codexRateLimits","expiresAt":null},{"status":"available","resetType":"codexRateLimits","expiresAt":2000000000},{"status":"available","resetType":"codexRateLimits","expiresAt":2000000000}]}}"#)
        let earliestOnly = AccountBalances(credits: nil, availableResets: 1,
            resetCredits: [.init(expiresAt: Date(timeIntervalSince1970: 2_000_000_000))])
        let lines = balance.lines(language: .english)
        #expect(lines.count == 3)
        #expect(lines[1] == "Available resets: 4")
        #expect(lines.last == earliestOnly.lines(language: .english).last)
        #expect(lines.last?.hasPrefix("Next reset expiry: ") == true)
    }

    @Test func noExpiryRequiresCompleteDetails() throws {
        let noExpiry = try parse(#"{"rateLimitResetCredits":{"availableCount":1,"credits":[{"status":"available","resetType":"codexRateLimits","expiresAt":null}]}}"#)
        #expect(noExpiry.lines(language: .english).last == "Resets do not expire")
        let partial = AccountBalances(credits: nil, availableResets: 2, resetCredits: noExpiry.resetCredits)
        #expect(partial.lines(language: .english).last == "Reset expiry unavailable")
    }

    @Test func redeemedAndUnknownResetTypesAreNotAnAvailableHistory() throws {
        let balance = try parse(#"{"rateLimitResetCredits":{"availableCount":1,"credits":[{"status":"redeemed","resetType":"codexRateLimits","expiresAt":2000000000},{"status":"available","resetType":"unknown","expiresAt":2000000000},{"status":"available","resetType":"codexRateLimits"},{"status":"available","resetType":"codexRateLimits","expiresAt":2000000000}]}}"#)
        #expect(balance.resetCredits?.count == 1)
        #expect(balance.availableResets == 1)
    }

    @Test func explicitZeroAndUnlimitedRemainDistinct() throws {
        let zero = try parse(#"{"rateLimits":{"credits":{"hasCredits":false,"unlimited":false,"balance":null}},"rateLimitResetCredits":{"availableCount":0,"credits":[]}}"#)
        #expect(zero.lines(language: .english) == ["Credits: 0", "Available resets: 0"])
        let unlimited = try parse(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":true,"balance":null}}}"#)
        #expect(unlimited.lines(language: .english).first == "Credits: Unlimited")
    }

    @Test func creditBalancesDisplayWholeCreditsWithoutChangingTheStoredBalance() {
        for (raw, display) in [("288.441425000", "288"), ("125.99", "125"), ("0.75", "0"), ("1234.50", "1,234")] {
            let balance = AccountBalances(credits: .init(hasCredits: true, unlimited: false, balance: raw),
                availableResets: nil, resetCredits: nil)
            #expect(balance.lines(language: .english).first == "Credits: \(display)")
            #expect(balance.credits?.balance == raw)
        }
    }

    @Test func balanceOnlyCacheRoundTripsAndOldCachesStillDecode() throws {
        let id = UUID()
        let balance = try parse(#"{"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#)
        let entry = UsageCacheEntry(profileID: id, usage: nil, fetchedAt: Date(), balances: balance)
        #expect(try JSONDecoder().decode(UsageCacheEntry.self, from: JSONEncoder().encode(entry)) == entry)
        let old = Data("{\"profileID\":\"\(id)\",\"usage\":{\"remainingPercent\":42,\"resetsAt\":0},\"fetchedAt\":0}".utf8)
        let decoded = try JSONDecoder().decode(UsageCacheEntry.self, from: old)
        #expect(decoded.usage?.remainingPercent == 42)
        #expect(decoded.balances == nil)
    }
}
