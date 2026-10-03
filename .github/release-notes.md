On Windows, the switcher now follows the Codex CLI installed by Codex Desktop when no `CODEX_CLI_PATH` override is set, so account and usage refreshes use the current Desktop runtime even when an older CLI appears earlier on `PATH`.

A deliberate `CODEX_CLI_PATH` override takes precedence. A missing override command now reports an error rather than silently selecting the installed Desktop runtime.

Installing the update does not switch accounts or close Codex.

Download the Windows x64 EXE or the macOS 14+ Apple Silicon DMG from Assets. Both include SHA-256 checksum files. Quit the existing switcher from its tray/menu-bar menu before replacing it; saved profiles remain in their existing data directory.

The Mac build is ad-hoc signed and not notarised. If first launch is blocked, follow [Apple's instructions](https://support.apple.com/en-gb/102445) to use System Settings → Privacy & Security → Open Anyway for this app. Managed Macs may prohibit this. Intel Macs are not included. Windows is also unsigned.

This is an independent fork of [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher), with the original MIT licence and attribution preserved.
