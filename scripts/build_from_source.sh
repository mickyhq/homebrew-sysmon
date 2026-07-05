#!/usr/bin/env bash
#==================================================================
#  sysmon — Build from source (NO Xcode GUI required)
#==================================================================
#  Requirements:
#    - macOS 13+
#    - Xcode Command Line Tools (xcode-select --install)
#      (provides swiftc, xcrun, codesign, hdiutil)
#    - A valid code-signing identity (for distribution) or
#      set SIGN_IDENTITY="" to skip signing (ad-hoc for testing)
#
#  Usage:
#    ./scripts/build_from_source.sh
#
#  Output:
#    build/sysmon.app              (the signed application bundle)
#    build/sysmon-latest.dmg       (distribution disk image)
#==================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Configurable settings ----------
APP_NAME="sysmon"
WIDGET_NAME="sysmonWidget"
BUNDLE_ID="com.sysmon.app"
WIDGET_BUNDLE_ID="${BUNDLE_ID}.widget"
APP_GROUP="group.com.sysmon.shared"
SIGN_IDENTITY="${SYS_SIGN_IDENTITY:-}"   # e.g. "Developer ID Application: ..." or leave empty for ad-hoc
MIN_VERSION="13.0"

# Read version from VERSION file (single source of truth)
VERSION_FILE="$PROJECT_DIR/VERSION"
if [ -f "$VERSION_FILE" ]; then
    VERSION="$(head -1 "$VERSION_FILE" | tr -d '[:space:]')"
else
    VERSION="1.0"
fi

# Notarization settings (optional)
NOTARY_APPLE_ID="${SYS_NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${SYS_NOTARY_TEAM_ID:-}"
NOTARY_KEYCHAIN_PROFILE="${SYS_NOTARY_KEYCHAIN_PROFILE:-sysmon-notary}"
# -------------------------------------------
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"
DMG_PATH="$BUILD_DIR/sysmon-latest.dmg"

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_step() { echo -e "${GREEN}[BUILD]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------- Prerequisites ----------
check_tools() {
    for tool in swiftc xcrun codesign hdiutil plutil sips iconutil; do
        if ! command -v "$tool" &>/dev/null; then
            log_err "$tool not found. Install Xcode Command Line Tools: xcode-select --install"
            exit 1
        fi
    done
    log_info "All required tools found."
}

# ---------- Gather SDK paths ----------
setup_sdk() {
    SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
    FRAMEWORKS="$SDK_PATH/System/Library/Frameworks"
    SWIFT_MODULES="$SDK_PATH/usr/lib/swift"
    log_info "SDK: $SDK_PATH"
}

# ---------- Compile main app executable ----------
compile_app() {
    log_step "Compiling main app executable..."

    local EXE_DIR="$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$EXE_DIR"

    local SHARED="$PROJECT_DIR/Shared"
    local MAIN="$PROJECT_DIR/sysmon"

    swiftc \
        -sdk "$SDK_PATH" \
        -target "arm64-apple-macos$MIN_VERSION" \
        -F "$FRAMEWORKS" \
        -I "$SWIFT_MODULES" \
        -module-name "$APP_NAME" \
        -parse-as-library \
        -O \
        -framework SwiftUI \
        -framework AppKit \
        \
        "$SHARED/SystemMonitorData.swift" \
        "$SHARED/SystemMonitorEngine.swift" \
        "$SHARED/AppGroupStore.swift" \
        "$MAIN/MenuBarViewModel.swift" \
        "$MAIN/MenuBarLabelView.swift" \
        "$MAIN/StatsDetailView.swift" \
        "$MAIN/StatusBarController.swift" \
        "$MAIN/sysmonApp.swift" \
        \
        -o "$EXE_DIR/$APP_NAME"

    log_info "Main executable compiled: $EXE_DIR/$APP_NAME"
}

# ---------- Compile Widget Extension ----------
compile_widget() {
    log_step "Compiling Widget extension..."

    local EXE_DIR="$WIDGET_BUNDLE/Contents/MacOS"
    mkdir -p "$EXE_DIR"

    local SHARED="$PROJECT_DIR/Shared"
    local WIDGET="$PROJECT_DIR/sysmonWidget"

    swiftc \
        -sdk "$SDK_PATH" \
        -target "arm64-apple-macos$MIN_VERSION" \
        -F "$FRAMEWORKS" \
        -I "$SWIFT_MODULES" \
        -module-name "$WIDGET_NAME" \
        -parse-as-library \
        -O \
        -framework SwiftUI \
        -framework WidgetKit \
        -framework AppKit \
        \
        "$SHARED/SystemMonitorData.swift" \
        "$SHARED/AppGroupStore.swift" \
        "$WIDGET/SystemStatsWidgetView.swift" \
        "$WIDGET/sysmonWidget.swift" \
        \
        -o "$EXE_DIR/$WIDGET_NAME"

    log_info "Widget executable compiled: $EXE_DIR/$WIDGET_NAME"
}

# ---------- Create app icon ----------
create_app_icon() {
    log_step "Creating app icon..."

    local SOURCE_ICON="$PROJECT_DIR/images/sysmon.png"
    local ICONSET="$BUILD_DIR/sysmon.iconset"
    local RESOURCES="$APP_BUNDLE/Contents/Resources"

    mkdir -p "$ICONSET" "$RESOURCES"

    sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
    cp "$SOURCE_ICON" "$ICONSET/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET" -o "$RESOURCES/sysmon.icns"
    rm -rf "$ICONSET"

    log_info "App icon created: $RESOURCES/sysmon.icns"
}

# ---------- Create Info.plist for app ----------
create_app_plist() {
    local PLIST="$APP_BUNDLE/Contents/Info.plist"
    cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleDisplayName</key>             <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>              <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
    <key>CFBundleName</key>                    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleIconFile</key>                <string>sysmon.icns</string>
    <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
    <key>CFBundleVersion</key>                 <string>1</string>
    <key>LSMinimumSystemVersion</key>          <string>$MIN_VERSION</string>
    <key>LSUIElement</key>                     <true/>
</dict>
</plist>
EOF
    log_info "App Info.plist created."
}

# ---------- Create Info.plist for widget ----------
create_widget_plist() {
    local PLIST="$WIDGET_BUNDLE/Contents/Info.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>       <string>en</string>
    <key>CFBundleDisplayName</key>             <string>$WIDGET_NAME</string>
    <key>CFBundleExecutable</key>              <string>$WIDGET_NAME</string>
    <key>CFBundleIdentifier</key>              <string>$WIDGET_BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>   <string>6.0</string>
    <key>CFBundleName</key>                    <string>$WIDGET_NAME</string>
    <key>CFBundlePackageType</key>             <string>XPC!</string>
    <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
    <key>CFBundleVersion</key>                 <string>1</string>
    <key>LSMinimumSystemVersion</key>          <string>$MIN_VERSION</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
EOF
    log_info "Widget Info.plist created."
}

# ---------- Create entitlements ----------
create_entitlements() {
    # App entitlements
    local APP_ENT="$BUILD_DIR/sysmon.entitlements"
    cat > "$APP_ENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>           <true/>
    <key>com.apple.security.application-groups</key>
    <array><string>$APP_GROUP</string></array>
</dict>
</plist>
EOF

    # Widget entitlements
    local WIDGET_ENT="$BUILD_DIR/sysmonWidget.entitlements"
    cat > "$WIDGET_ENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>           <true/>
    <key>com.apple.security.application-groups</key>
    <array><string>$APP_GROUP</string></array>
</dict>
</plist>
EOF
    log_info "Entitlements created in $BUILD_DIR"
}

# ---------- Code sign ----------
sign_bundles() {
    local ENT_APP="$BUILD_DIR/sysmon.entitlements"
    local ENT_WIDGET="$BUILD_DIR/sysmonWidget.entitlements"

    local CODESIGN_OPTS="--force --deep --options runtime --timestamp"

    if [ -n "$SIGN_IDENTITY" ]; then
        log_step "Code-signing with identity: $SIGN_IDENTITY"
        local SIGN_ARG="--sign $SIGN_IDENTITY"
    else
        log_info "No signing identity provided — using ad-hoc signature (-s -)"
        local SIGN_ARG="--sign -"
    fi

    # Sign widget first (inside PlugIns)
    log_info "Signing widget..."
    codesign $CODESIGN_OPTS $SIGN_ARG \
        --entitlements "$ENT_WIDGET" \
        "$WIDGET_BUNDLE"

    # Sign main app
    log_info "Signing main app..."
    codesign $CODESIGN_OPTS $SIGN_ARG \
        --entitlements "$ENT_APP" \
        "$APP_BUNDLE"

    # Verify
    log_info "Verifying signature..."
    codesign --verify --verbose=4 "$APP_BUNDLE" 2>&1 || {
        log_err "Code-sign verification failed."
        exit 1
    }
    log_info "Signature OK."
}

# ---------- Create DMG ----------
package_dmg() {
    log_step "Packaging DMG..."

    # Remove old DMG if present
    rm -f "$DMG_PATH"

    hdiutil create -ov \
        -srcfolder "$APP_BUNDLE" \
        -volname "$APP_NAME" \
        -format UDZO \
        "$DMG_PATH"

    log_step "DMG created at: $DMG_PATH"
}

# ---------- Notarize and staple DMG ----------
notarize_dmg() {
    # Skip if not signing for distribution (ad-hoc)
    if [ -z "$SIGN_IDENTITY" ]; then
        log_info "Skipping notarization (ad-hoc signature)."
        return
    fi

    # Skip if notary credentials not provided
    if [ -z "$NOTARY_APPLE_ID" ] && [ -z "$NOTARY_TEAM_ID" ] && [ -z "$NOTARY_KEYCHAIN_PROFILE" ]; then
        log_info "Skipping notarization (no credentials provided)."
        log_info "Set SYS_NOTARY_APPLE_ID, SYS_NOTARY_TEAM_ID, or SYS_NOTARY_KEYCHAIN_PROFILE to enable."
        return
    fi

    log_step "Submitting DMG for notarization..."

    # Build notarytool args based on what's provided
    local NOTARY_ARGS=("submit" "$DMG_PATH" "--wait")

    if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
        NOTARY_ARGS+=("--keychain-profile" "$NOTARY_KEYCHAIN_PROFILE")
    elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_TEAM_ID" ]; then
        NOTARY_ARGS+=("--apple-id" "$NOTARY_APPLE_ID" "--team-id" "$NOTARY_TEAM_ID")
    fi

    xcrun notarytool "${NOTARY_ARGS[@]}" 2>&1 || {
        log_err "Notarization failed."
        exit 1
    }

    log_step "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH" 2>&1 || {
        log_err "Stapling failed."
        exit 1
    }

    log_step "Notarization complete. DMG is ready for distribution."
}

# ---------- Clean ----------
clean() {
    log_step "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# ---------- Post-build summary ----------
print_summary() {
    echo ""
    echo "==============================================="
    echo "  Build complete!"
    echo "==============================================="
    echo ""
    echo "  Version:      $VERSION"
    echo "  App bundle:   $APP_BUNDLE"
    echo "  Widget:       $WIDGET_BUNDLE"
    echo "  DMG:          $DMG_PATH"
    echo ""
    if [ -n "$SIGN_IDENTITY" ]; then
        echo "  Signed with:  $SIGN_IDENTITY"
        if [ -n "$NOTARY_APPLE_ID" ] || [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
            echo "  Notarized:    yes (stapled)"
        else
            echo "  Notarized:    no"
            echo ""
            echo "  To notarize, rebuild with:"
            echo "    SYS_NOTARY_KEYCHAIN_PROFILE=sysmon-notary ./scripts/build_from_source.sh"
            echo ""
            echo "  Or manually:"
            echo "    xcrun notarytool submit $DMG_PATH --keychain-profile sysmon-notary --wait"
            echo "    xcrun stapler staple $DMG_PATH"
        fi
    else
        echo "  Signed with:  ad-hoc (testing only)"
        echo ""
        echo "  For distribution, rebuild with:"
        echo "    SYS_SIGN_IDENTITY='Developer ID Application: ...' \\"
        echo "      SYS_NOTARY_KEYCHAIN_PROFILE=sysmon-notary \\"
        echo "      ./scripts/build_from_source.sh"
    fi
    echo ""
}

# =================== MAIN ===================
main() {
    echo ""
    echo "==============================================="
    echo "  sysmon — Command-Line Build"
    echo "==============================================="
    echo ""

    log_info "Building sysmon v$VERSION..."
    check_tools
    setup_sdk
    clean
    compile_app
    compile_widget
    create_app_icon
    create_app_plist
    create_widget_plist
    create_entitlements
    sign_bundles
    package_dmg
    notarize_dmg
    print_summary
}

main "$@"
