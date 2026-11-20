#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir=${QUOTABAR_APP_DIR:-"$HOME/Applications"}
app_bundle="$app_dir/QuotaBar.app"

cd "$repo_dir"
swift build -c release

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp .build/release/quota-bar "$app_bundle/Contents/MacOS/quota-bar"
cp LICENSE "$app_bundle/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$app_bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
ditto .build/release/QuotaBar_QuotaBar.bundle "$app_bundle/Contents/Resources/QuotaBar_QuotaBar.bundle"

plutil -create xml1 "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleName -string "QuotaBar" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "QuotaBar" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "dev.johney4415.quotabar" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "quota-bar" "$app_bundle/Contents/Info.plist"
plutil -replace CFBundlePackageType -string "APPL" "$app_bundle/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "14.0" "$app_bundle/Contents/Info.plist"
plutil -replace LSUIElement -bool true "$app_bundle/Contents/Info.plist"

codesign --force --deep --sign - "$app_bundle"

printf 'Installed app: %s\n' "$app_bundle"
printf 'Open QuotaBar.app, then choose Connect Claude Code if needed.\n'
