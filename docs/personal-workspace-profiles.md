# Personal and workspace profiles

This fork adds separate personal and workspace entries for a ChatGPT login that uses the same email address. The original project is [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher); the request is recorded in [Discussion 9](https://github.com/liuzhao1225/codex-account-switcher/discussions/9).

In Manage Accounts, add the login once for Personal, then again for the workspace. The browser sign-in requests the full account chooser. Each entry shows its account context, and switch/removal confirmations repeat it. OpenAI controls the actual browser screens; live acceptance must confirm that both contexts are offered for the account concerned. If the browser still selects the wrong context, cancel instead of saving it. Register Current Account can save an account context already selected in Codex.

The app stores each context's complete credential separately. It identifies the selected account using `tokens.account_id` in that credential, with the ID-token account claim as a compatibility source. It also compares emails when both are present. The `account/read` response alone is insufficient because the current Codex protocol supplies email and plan but omits account identity. A known account ID never matches an unidentified profile by email alone.

Existing profiles recover missing identity and plan metadata from their own saved credential. Profile IDs, saved credential bytes, active selection and cached usage are preserved. Missing or unreadable metadata is left unchanged; it is never inferred from the active account's credential.

## Credits and available resets

Each profile refreshes its own `account/rateLimits/read` response. The account row shows:

- remaining usage credits, or Unlimited when explicitly reported;
- the number of available usage-limit resets;
- only the next expiry date among available reset credits, or an explicit message when none expire;
- the existing weekly allowance and optional five-hour allowance with their scheduled reset times.

Credit balances remain visible for accounts that have no weekly allowance window. Missing values are shown as unavailable rather than zero. The service's reset count is authoritative: its detail list may be shorter, or absent. With partial details, the earliest supplied date is labelled “Next known reset expiry”; without a date, expiry is unavailable unless all available resets are explicitly non-expiring. Dates use the computer's local time zone. The wider account window gives these details more room without listing every expiry.

This is read-only tracking. It does not redeem a reset, buy credits, infer entitlement from allowance percentages, or keep reset-use history. Opaque reset identifiers are not stored or displayed. The available balance response has no purchased-credit expiry field, so the app does not invent one.

Balances are cached per saved profile, alongside usage. Cached values are labelled until a fresh read succeeds, and remain labelled if refresh fails. Removing an inactive profile also removes its cache entry.

Older Codex runtimes may omit reset-credit metadata. The UI reports it as unavailable; use an up-to-date Codex runtime to obtain the detailed response. No separate account API or browser cookie integration is used.

## Verification

Synthetic tests cover separate same-email contexts, duplicate rejection, switching in both directions, restoration after a wrong-workspace response, legacy identity hydration, independent balance caches, credit-only accounts, unknown versus zero balances, partial expiry details and omission of redeemed credits. Native Windows checks exercise same-email account rows and confirmations.

Real browser account selection and a complete Codex Desktop restart require interactive acceptance after active tasks have finished. Windows tests do not establish macOS runtime behaviour.
