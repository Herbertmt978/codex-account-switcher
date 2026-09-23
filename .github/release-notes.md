This fork adds separate Personal and Workspace profiles for accounts that share an email address.

- Rediscover Codex Desktop for every handoff and match Store processes by stable app identity across package updates.
- Explain revoked sign-ins with recovery steps and mark cached balances as stale after refresh fails.
- Read each profile's usage, credit balance and current available reset count independently.
- Show whole credit numbers, equal-width usage tracks and only the next reset-credit expiry in a wider window.
- Refresh new profiles immediately and prevent concurrent Windows account reads from stalling.
- Keep update links within this fork. Mac updates are downloaded and installed manually.

The revised Windows account handoff passed isolated checks but has not yet completed a live switch between saved profiles. Please test it after installing this release.

Download the Windows x64 EXE or the macOS 14+ Apple Silicon DMG from Assets. Both include SHA-256 checksum files. Quit the existing switcher from its tray/menu-bar menu before replacing it; saved profiles remain in their existing data directory.

**Mac installation:** open the DMG and drag the app to Applications. This build is ad-hoc signed, not signed with an Apple Developer ID or notarised by Apple. If first launch is blocked, follow [Apple's instructions](https://support.apple.com/en-gb/102445) to use System Settings → Privacy & Security → Open Anyway for this app. Managed Macs may prohibit this. Intel Macs are not included in this release.

Windows is also unsigned. Neither version redeems resets or records resets used. This is an independent fork of [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher), with the original MIT licence and attribution preserved.
