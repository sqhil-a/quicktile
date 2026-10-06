#!/bin/bash
set -euo pipefail
# Requires an already signed Developer ID archive. Credentials live in Keychain.
qt_release_app="${1:?Usage: notarize-companion.sh APP_PATH KEYCHAIN_PROFILE OUTPUT_DIRECTORY}"
qt_notary_profile="${2:?Supply a notarytool Keychain profile name}"
qt_release_output="${3:?Supply an output directory}"
[[ -d "$qt_release_app" && "$qt_release_app" == *.app ]] || { echo "Choose a signed .app" >&2; exit 1; }
# Select full Xcode only for this process and its children; never change xcode-select.
qt_release_developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$qt_release_developer_dir" ]]; then
    qt_release_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    if [[ ! -x "$qt_release_developer_dir/usr/bin/xcodebuild" ]]; then
        qt_release_developer_dir="/Applications/Xcode.app/Contents/Developer"
    fi
fi
[[ "$qt_release_developer_dir" != *.app ]] || qt_release_developer_dir="$qt_release_developer_dir/Contents/Developer"
[[ -x "$qt_release_developer_dir/usr/bin/xcodebuild" ]] || {
    echo "Set DEVELOPER_DIR to a full Xcode installation." >&2; exit 1;
}
export DEVELOPER_DIR="$qt_release_developer_dir"
/usr/bin/xcrun --find notarytool >/dev/null
/usr/bin/xcrun --find stapler >/dev/null
codesign --verify --strict --deep "$qt_release_app"
codesign -dv "$qt_release_app" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application'
mkdir -p "$qt_release_output"
qt_release_zip="$qt_release_output/QuickTileMac-submission.zip"
ditto -c -k --keepParent "$qt_release_app" "$qt_release_zip"
xcrun notarytool submit "$qt_release_zip" --keychain-profile "$qt_notary_profile" --wait
xcrun stapler staple "$qt_release_app"
xcrun stapler validate "$qt_release_app"
spctl --assess --type execute --verbose=2 "$qt_release_app"
ditto -c -k --keepParent "$qt_release_app" "$qt_release_output/QuickTileMac.zip"
shasum -a 256 "$qt_release_output/QuickTileMac.zip" > "$qt_release_output/QuickTileMac.sha256"
