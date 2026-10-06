#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
qt_release_target="${1:?Usage: archive-release.sh iphone|mac TEAM_ID BUILD_NUMBER}"
qt_release_team="${2:?Supply your signing team ID}"
qt_release_build="${3:?Supply an increasing build number}"
[[ "$qt_release_team" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid team ID" >&2; exit 1; }
[[ "$qt_release_build" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 1; }
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
mkdir -p .build/releases
case "$qt_release_target" in
iphone)
    xcodebuild -project QuickTile.xcodeproj -scheme QuickTile -configuration Release \
      -destination 'generic/platform=iOS' -archivePath .build/releases/QuickTile.xcarchive \
      DEVELOPMENT_TEAM="$qt_release_team" CURRENT_PROJECT_VERSION="$qt_release_build" archive
    ;;
mac)
    xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac -configuration Release \
      -destination 'generic/platform=macOS' -archivePath .build/releases/QuickTileMac.xcarchive \
      DEVELOPMENT_TEAM="$qt_release_team" CURRENT_PROJECT_VERSION="$qt_release_build" \
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Developer ID Application' ARCHS='arm64 x86_64' archive
    ;;
*) echo "Choose iphone or mac" >&2; exit 1 ;;
esac
