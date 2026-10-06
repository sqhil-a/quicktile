#!/bin/sh
set -eu

# Called by the Mac target before bundle signing. No user hook configuration is touched.
: "${SRCROOT:?}" "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}"
qt_helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
qt_helper_temp="${DERIVED_FILE_DIR:-$TARGET_BUILD_DIR}/QuickTileAgentHelper"
mkdir -p "$qt_helper_dir" "$qt_helper_temp"
qt_helper_sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
qt_helper_arches="${ARCHS:-$(uname -m)}"
qt_helper_objects=""
for qt_helper_arch in $qt_helper_arches; do
    qt_helper_binary="$qt_helper_temp/$qt_helper_arch"
    xcrun swiftc -O -parse-as-library -sdk "$qt_helper_sdk" -module-cache-path "$qt_helper_temp/ModuleCache" \
        -target "$qt_helper_arch-apple-macosx${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
        "$SRCROOT/Shared/Sources/QuickTileCore/AgentActivity.swift" \
        "$SRCROOT/Scripts/AgentEventHelper.swift" -o "$qt_helper_binary"
    qt_helper_objects="$qt_helper_objects $qt_helper_binary"
done
# Derived build paths may contain spaces, so pass the selected binaries individually.
set --
for qt_helper_arch in $qt_helper_arches; do set -- "$@" "$qt_helper_temp/$qt_helper_arch"; done
xcrun lipo -create "$@" -output "$qt_helper_dir/QuickTileAgentEvent"
chmod 755 "$qt_helper_dir/QuickTileAgentEvent"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    qt_helper_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    [ -n "$qt_helper_identity" ] || qt_helper_identity=-
    if [ "$qt_helper_identity" = - ]; then
        codesign --force --sign - --options runtime --timestamp=none "$qt_helper_dir/QuickTileAgentEvent"
    else
        codesign --force --sign "$qt_helper_identity" --options runtime --timestamp "$qt_helper_dir/QuickTileAgentEvent"
    fi
fi
