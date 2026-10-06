The portable Windows switcher now protects its EXE from being moved, deleted or replaced while running. This prevents later `FileNotFoundException` failures when .NET needs another bundled assembly. Quit the switcher from its tray menu before moving or replacing its EXE.

When the Codex executable is missing or its app-server cannot start, the error now asks you to ensure Codex Desktop is installed and updated, restart both apps and retry. Startup diagnostic details remain available.

Installing the update does not switch accounts or close Codex.

Download the Windows x64 EXE or the macOS 14+ Apple Silicon DMG from Assets. Both include SHA-256 checksum files. Quit the existing switcher from its tray/menu-bar menu before replacing it; saved profiles remain in their existing data directory.

The Mac build is ad-hoc signed and not notarised. If first launch is blocked, follow [Apple's instructions](https://support.apple.com/en-gb/102445) to use System Settings → Privacy & Security → Open Anyway for this app. Managed Macs may prohibit this. Intel Macs are not included. Windows is also unsigned.

This is an independent fork of [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher), with the original MIT licence and attribution preserved.
