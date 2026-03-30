#!/bin/bash
# Build, sign, and package ChitChat into a DMG for distribution.
# Usage: ./scripts/build-dmg.sh
#
# Prerequisites:
#   - Xcode command line tools
#   - Developer ID certificate (for signing) — optional, will skip if not found
#
# Output: build/ChitChat-1.0.0.dmg

set -euo pipefail

APP_NAME="ChitChat"
SCHEME="ChitChat"
PROJECT="ChitChat.xcodeproj"
CONFIG="Release"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-1.0.0"

echo "=== Building ${APP_NAME} (${CONFIG}) ==="
xcodebuild -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    build

APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/${CONFIG}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: Build output not found at ${APP_PATH}"
    exit 1
fi

echo "=== Build successful ==="

# Sign if Developer ID is available
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
if [ -n "${IDENTITY}" ]; then
    echo "=== Signing with: ${IDENTITY} ==="
    codesign --deep --force --options runtime \
        --sign "${IDENTITY}" \
        "${APP_PATH}"
    echo "=== Signed ==="
else
    echo "=== No Developer ID found, skipping code signing ==="
    echo "    (App will show 'unidentified developer' warning on other Macs)"
fi

# Create DMG
echo "=== Creating DMG ==="
mkdir -p "${BUILD_DIR}"
DMG_TEMP="${BUILD_DIR}/${DMG_NAME}-temp.dmg"
DMG_FINAL="${BUILD_DIR}/${DMG_NAME}.dmg"

# Remove old DMG if exists
rm -f "${DMG_TEMP}" "${DMG_FINAL}"

# Create temporary DMG
hdiutil create -srcfolder "${APP_PATH}" \
    -volname "${APP_NAME}" \
    -fs HFS+ \
    -format UDRW \
    "${DMG_TEMP}"

# Mount and customize
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "${DMG_TEMP}" | grep "/Volumes/" | sed 's/.*\(\/Volumes\/.*\)/\1/')

# Add Applications symlink
ln -sf /Applications "${MOUNT_DIR}/Applications"

# Unmount
hdiutil detach "${MOUNT_DIR}"

# Convert to compressed read-only DMG
hdiutil convert "${DMG_TEMP}" -format UDZO -o "${DMG_FINAL}"
rm -f "${DMG_TEMP}"

echo ""
echo "=== Done! ==="
echo "DMG: ${DMG_FINAL}"
echo "Size: $(du -h "${DMG_FINAL}" | cut -f1)"

# Notarize if credentials are available
if xcrun notarytool history --keychain-profile "AC_PASSWORD" > /dev/null 2>&1; then
    echo ""
    echo "=== Notarizing ==="
    xcrun notarytool submit "${DMG_FINAL}" \
        --keychain-profile "AC_PASSWORD" \
        --wait
    xcrun stapler staple "${DMG_FINAL}"
    echo "=== Notarized and stapled ==="
else
    echo ""
    echo "To notarize (optional):"
    echo "  1. Store credentials: xcrun notarytool store-credentials AC_PASSWORD --apple-id YOUR_ID --team-id YOUR_TEAM"
    echo "  2. Run: xcrun notarytool submit ${DMG_FINAL} --keychain-profile AC_PASSWORD --wait"
    echo "  3. Run: xcrun stapler staple ${DMG_FINAL}"
fi
