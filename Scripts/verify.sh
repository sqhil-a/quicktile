#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use a full Xcode without changing the machine's global developer selection.
qt_verify_developer_dir="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p 2>/dev/null || true)}"
[[ "$qt_verify_developer_dir" != *.app ]] || qt_verify_developer_dir="$qt_verify_developer_dir/Contents/Developer"
if [[ ! -x "$qt_verify_developer_dir/usr/bin/xcodebuild" ]]; then
    qt_verify_developer_dir="/Applications/Xcode.app/Contents/Developer"
fi
[[ -x "$qt_verify_developer_dir/usr/bin/xcodebuild" ]] || {
    echo "Set DEVELOPER_DIR to a full Xcode installation." >&2; exit 1;
}
export DEVELOPER_DIR="$qt_verify_developer_dir"
swift test --package-path Shared
swift Scripts/verify-icon-geometry.swift
xcodebuild -project QuickTile.xcodeproj -scheme QuickTile -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac -destination 'platform=macOS' -derivedDataPath .build/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project QuickTile.xcodeproj -scheme QuickTileMac -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/mac-tests CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build-for-testing
xcrun xctest .build/mac-tests/Build/Products/Debug/QuickTileMacTests.xctest
