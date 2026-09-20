#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
export RELEASE_REPOSITORY=Herbertmt978/codex-account-switcher
export SWIFT_BUILD_ARCH=arm64
export CODESIGN_IDENTITY=-
test "$(uname -m)" = arm64
version=$(node scripts/validate-release-tag.mjs "v${RELEASE_VERSION:?Set RELEASE_VERSION}")
app_path=$(./scripts/package-local-app.sh | tail -n 1)
artifact="$PWD/.build/artifacts/Codex-Account-Switcher-macos-arm64.dmg"
staging=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/codex-fork-dmg.XXXXXX")
mounted=false
app_pid=
cleanup() {
  if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi
  if [[ "$mounted" == true ]]; then hdiutil detach "$staging/mount" >/dev/null 2>&1 || true; fi
  rm -rf "$staging"
}
trap cleanup EXIT

codesign --verify --deep --strict "$app_path"
codesign --display --verbose=4 "$app_path" 2>&1 | grep -F 'Signature=adhoc'
test "$(lipo -archs "$app_path/Contents/MacOS/CodexAccountSwitcher")" = arm64
mkdir -p "$staging/root" "$staging/mount" "$staging/empty-codex-home" "$(dirname "$artifact")"
ditto "$app_path" "$staging/root/Codex Account Switcher.app"
cp LICENSE "$staging/root/LICENSE.txt"
ln -s /Applications "$staging/root/Applications"
hdiutil create -ov -volname "Codex Account Switcher" -srcfolder "$staging/root" -format UDZO "$artifact"
hdiutil verify "$artifact"
hdiutil attach -readonly -nobrowse -mountpoint "$staging/mount" "$artifact"
mounted=true
mounted_app="$staging/mount/Codex Account Switcher.app"
codesign --verify --deep --strict "$mounted_app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :SwitcherReleasePage' "$mounted_app/Contents/Info.plist")" = "https://github.com/$RELEASE_REPOSITORY/releases/latest"
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$mounted_app/Contents/Info.plist" >/dev/null 2>&1; then
  echo 'Fork packages must not use the upstream Sparkle feed.' >&2
  exit 1
fi
test -s "$mounted_app/Contents/Resources/LICENSE.txt"
test -s "$mounted_app/Contents/Resources/AppIcon.icns"
CODEX_HOME="$staging/empty-codex-home" "$mounted_app/Contents/MacOS/CodexAccountSwitcher" > "$staging/launch.log" 2>&1 &
app_pid=$!
sleep 3
if ! kill -0 "$app_pid" 2>/dev/null; then cat "$staging/launch.log"; exit 1; fi
kill "$app_pid"
wait "$app_pid" 2>/dev/null || true
app_pid=
hdiutil detach "$staging/mount"
mounted=false
(cd "$(dirname "$artifact")" && shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256")
echo 'PASS: ad-hoc signature, arm64 architecture, mounted DMG metadata, fork update channel and app launch.'
echo "$artifact"
