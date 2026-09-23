The active account is listed first. Its usage is read from the verified live Codex login, and its saved credential is updated at startup and during periodic refreshes. Saved credentials for other accounts remain separate. The switcher checks account identity before updating a saved credential.

Personal account rows now show the subscription tier reported by Codex, including Free, Pro ×5 and Pro ×20. Subscription renewal dates are not available from Codex and are not shown.

This release also refreshes usage after a completed switch. The Windows account handoff has passed isolated checks; this release does not claim a new live handoff test. Installing the update does not switch accounts or close Codex.

Download the Windows x64 EXE or the macOS 14+ Apple Silicon DMG from Assets. Both include SHA-256 checksum files. Quit the existing switcher from its tray/menu-bar menu before replacing it; saved profiles remain in their existing data directory.

The Mac build is ad-hoc signed and not notarised. If first launch is blocked, follow [Apple's instructions](https://support.apple.com/en-gb/102445) to use System Settings → Privacy & Security → Open Anyway for this app. Managed Macs may prohibit this. Intel Macs are not included. Windows is also unsigned.

This is an independent fork of [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher), with the original MIT licence and attribution preserved.
