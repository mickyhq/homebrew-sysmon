#!/usr/bin/env bash
# ------------------------------------------------------------------
#  sysmon DMG Packaging Script
# ------------------------------------------------------------------
#  Usage:
#    1. Open sysmon.xcodeproj in Xcode
#    2. Select "Product > Archive" (or xcodebuild archive)
#    3. Run this script to generate a distribution-ready DMG
#       ./scripts/build_dmg.sh /path/to/sysmon.xcarchive
#
#  The script requires:
#     - macOS with Xcode and hdiutil installed
#     - Optional: create-dmg (brew install create-dmg) for a prettier DMG
# ------------------------------------------------------------------

set -euo pipefail

# ---------- Configuration ----------
APP_NAME="sysmon"
DMG_NAME="sysmon-latest"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Your Name (TEAMID)}"
USE_CREATE_DMG=false   # Set to true if `create-dmg` is installed via brew

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_step() { echo -e "${GREEN}[BUILD]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------- Validate Archives ----------
ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
    log_err "Usage: $0 <path-to-xcarchive>"
    exit 1
fi

ARCHIVE="${ARCHIVE%/}"                # strip trailing slash
EXPORT_DIR="${ARCHIVE}.signed"        # temp signed app bundle
DMG_BUILD="build/${DMG_NAME}.dmg"

log_step "Extracting .app from archive: $ARCHIVE"

APP_PATH=""
# Prefer the location inside an xcarchive from Xcode's Organizer
for path in \
    "${ARCHIVE}/Products/Applications/${APP_NAME}.app" \
    "${ARCHIVE}/"*/"Products/Applications/${APP_NAME}.app"; do
    if [ -d "$path" ]; then
        APP_PATH="$path"
        break
    fi
done

if [ -z "$APP_PATH" ]; then
    log_err "Could not find ${APP_NAME}.app inside the archive."
    log_err "Make sure you archived the main app target (not the widget)."
    exit 1
fi

log_step "Found app at: $APP_PATH"

# ---------- Re-sign (Optional but recommended) ----------
log_step "Re-signing .app with identity: $IDENTITY"

codesign --force --deep --options runtime \
    --entitlements "${ARCHIVE}/../Entitlements.plist" \
    --sign "$IDENTITY" \
    "$APP_PATH" 2>/dev/null || true

# Verify code-signature
log_step "Verifying code signature..."
codesign --verify --verbose=4 "$APP_PATH" || {
    log_err "Code-sign verification FAILED. Check your identity and entitlements."
    exit 1
}

# ---------- Create DMG ----------
mkdir -p build

if [ "$USE_CREATE_DMG" = true ] && command -v create-dmg &>/dev/null; then
    log_step "Using create-dmg for a nice disk image..."
    create-dmg \
        --volname "${APP_NAME} Installer" \
        --window-size 480 360 \
        --icon-size 100 \
        --app-drop-link 200 190 \
        "$DMG_BUILD" \
        "$APP_PATH"
else
    log_step "Using hdiutil to build raw DMG..."
    hdiutil create -ov -srcfolder "$APP_PATH" \
        -volname "${APP_NAME}" \
        -format UDZO \
        "$DMG_BUILD"
fi

log_step "DMG built at: ${DMG_BUILD}"
echo ""
echo "  Next steps:"
echo "  -----------"
echo "  1. Notarize the DMG:"
echo "     xcrun notarytool submit ${DMG_BUILD} --apple-id \"your@email.com\" --team-id TEAMID --wait"
echo "  2. Stable:"
echo "     xcrun stapler staple ${DMG_BUILD}"
echo ""
log_step "Done!"