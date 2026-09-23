# Personal and workspace profiles

This fork adds separate personal and workspace entries for a ChatGPT login that uses the same email address. The original project is [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher); the request is recorded in [Discussion 9](https://github.com/liuzhao1225/codex-account-switcher/discussions/9).

In Manage Accounts, add the login once for Personal, then again for the workspace. The browser sign-in requests the full account chooser. Each entry shows its account context, and switch/removal confirmations repeat it. OpenAI controls the actual browser screens; live acceptance must confirm that both contexts are offered for the account concerned. If the browser still selects the wrong context, cancel instead of saving it. Register Current Account can save an account context already selected in Codex.

The app stores each context's complete credential separately. It identifies the selected account using `tokens.account_id` in that credential, with the ID-token account claim as a compatibility source. It also compares emails when both are present. The `account/read` response alone is insufficient because the current Codex protocol supplies email and plan but omits account identity. A known account ID never matches an unidentified profile by email alone.

Existing profiles recover missing identity and plan metadata from their own saved credential. Profile IDs, saved credential bytes, active selection and cached usage are preserved. Missing or unreadable metadata is left unchanged; it is never inferred from the active account's credential.

The active profile appears first in account lists; the saved profile order is unchanged. Once the live Codex identity matches a saved profile, the switcher refreshes that profile's saved credential from Codex's active home at startup and during periodic refreshes. It checks the account identity again before copying, so an external sign-in to a different account cannot overwrite the selected profile. After a successful switch, the newly active account is refreshed. Inactive profiles continue to use their own saved credentials.

Personal profiles show the subscription tier reported by Codex beside their context, including Free, Pro ×5 and Pro ×20. The tier is refreshed from the confirmed active login. Subscription renewal dates are not shown because Codex's account response does not provide them.

## Credits and available resets

Each profile refreshes its own `account/rateLimits/read` response. The active profile uses the verified live Codex home; inactive profiles use their saved credential homes. The account row shows:

- remaining usage credits as whole numbers (rounded down for display), or Unlimited when explicitly reported;
- the number of available usage-limit resets;
- only the next expiry date among available reset credits, or an explicit message when none expire;
- the existing weekly allowance and optional five-hour allowance with their scheduled reset times.

Credit balances remain visible for accounts that have no weekly allowance window. Missing values are shown as unavailable rather than zero. The service's reset count is authoritative: its detail list may be shorter, or absent. With partial details, the earliest supplied date is labelled “Next known reset expiry”; without a date, expiry is unavailable unless all available resets are explicitly non-expiring. Dates use the computer's local time zone. The wider account window gives these details more room without listing every expiry.

This is read-only tracking. It does not redeem a reset, buy credits, infer entitlement from allowance percentages, or keep reset-use history. Opaque reset identifiers are not stored or displayed. The available balance response has no purchased-credit expiry field, so the app does not invent one.

Balances are cached per saved profile, alongside usage. Cached values are labelled until a fresh read succeeds, and remain labelled if refresh fails. Removing an inactive profile also removes its cache entry.

Newly signed-in or registered profiles refresh automatically, including when an earlier refresh is still running. Five-hour and weekly bars share the same track width; only their fill represents the remaining percentage. Raw credit balances retain their original precision in the cache.

Older Codex runtimes may omit reset-credit metadata. The UI reports it as unavailable; use an up-to-date Codex runtime to obtain the detailed response. No separate account API or browser cookie integration is used.

## Verification

Synthetic tests cover separate same-email contexts, duplicate rejection, switching in both directions, restoration after a wrong-workspace response, legacy identity hydration, independent balance caches, credit-only accounts, whole-number presentation, partial expiry details and omission of redeemed credits. They also cover active-first display, live usage with a revoked saved credential, credential refresh and refusal to copy another account's credential. Native Windows checks exercise same-email account rows, confirmations and equal-width progress tracks.

Windows reads Codex output on cancellable native pipe readers. Transport tests cover 32 simultaneous account reads, a silent server, sign-in cancellation, stderr drainage, and stopping an idle reader while its writer remains open.

Real browser account selection and a complete Codex Desktop restart require interactive acceptance after active tasks have finished. Windows tests do not establish macOS runtime behaviour.
