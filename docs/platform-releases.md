# Fork versions and releases

This fork shares one version and immutable `v<major>.<minor>.<patch>` tag across Windows x64 and macOS 14+ Apple Silicon. Both packages are built from that tag and published together as the latest release on Herbertmt978/codex-account-switcher.

## Test and publish

1. Set matching versions in CITATION.cff, the Mac packaging script, CodexClient, the host fallback and Windows metadata. Update the release notes and download instructions.
2. Complete local Windows/core/UI/package checks. PR CI also runs macOS tests, CoreChecks, DMG signature/metadata checks and an isolated Codex-home app launch.
3. Merge only after all checks pass. Create an annotated version tag on the verified main commit.
4. The Fork release workflow validates version sources and main ancestry, refuses existing releases, and reruns both platform checks and packaging.
5. Publication waits for both builds, verifies the DMG and EXE against their checksum files, creates a draft, then publishes it as Latest. Verify the public assets after publication. Do not overwrite a published version.

The original Developer ID/notarisation workflow is restricted to the upstream repository. This fork's Mac app uses an ad-hoc signature; it does not borrow the upstream author's identity, signing keys or update feed. The upstream website deployment is also restricted to the upstream repository.

## Mac installation

Download the DMG from this fork's release, open it and drag Codex Account Switcher to Applications. Quit an existing switcher before replacing it. Account data stays in the existing application-support directory.

The app is ad-hoc signed and is not notarised by Apple. If macOS blocks first launch, use the per-app **Open Anyway** option under **System Settings → Privacy & Security**, following [Apple's instructions](https://support.apple.com/en-gb/102445). An organisation-managed Mac may prevent this. Do not disable Gatekeeper globally. If macOS reports malware or a damaged app, stop and check the download and checksum instead of overriding that warning.

The DMG targets Apple Silicon (arm64), not Intel Macs. CI verifies the app's launch and package integrity; it cannot confirm the interactive Gatekeeper approval on every Mac. A normal Developer ID-signed and notarised release requires the fork owner's Apple Developer credentials.

## Updates and assets

Each release contains the Mac DMG, Windows EXE and one SHA-256 file per package. Windows checks this fork's releases and opens its download page. On Mac, Check for Updates opens this fork's latest release page; automatic checks/installations are unavailable for this distribution. No Sparkle appcast is published or consumed by fork Mac packages.

Both platforms use manual replacement. Closing the Windows title-bar window only hides it; choose Quit from the tray before replacing the executable. Saved profiles and active Codex credentials remain separate from the application package.