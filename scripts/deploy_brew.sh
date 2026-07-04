#!/usr/bin/env bash
# ==============================================================================
#  sysmon — Homebrew Cask Deployment Script (swiftc / no Xcode required)
# ==============================================================================
#  This script automates the complete macOS deployment pipeline using only the
#  Xcode Command Line Tools (swiftc, xcrun, codesign). No Xcode GUI or
#  xcodebuild needed.
#
#    1. Compile .app       — swiftc (main app + WidgetKit extension)
#    2. Assemble bundle    — Info.plist, PlugIns, icons, entitlements
#    3. Code Sign          — Developer ID Application certificate
#    4. Notarize .app      — Apple Notary service, staple ticket
#    5. Package DMG        — hdiutil (UDZO read-only compressed)
#    6. Notarize DMG       — Notarize + staple the final .dmg
#    7. Homebrew Cask      — Generate the Ruby Cask block + SHA-256
#
# ==============================================================================
#  PREREQUISITES
# ==============================================================================
#
#   1. macOS 13+ with Xcode Command Line Tools.
#      Install: xcode-select --install
#
#   2. A valid Apple Developer ID Application certificate in your keychain.
#      Verify: security find-identity -v -p basic | grep "Developer ID"
#
#   3. An App-Specific Password for notarization (appleid.apple.com).
#
#   4. Required environment variables:
#
#        export SYS_APPLE_ID="you@example.com"
#        export SYS_APPLE_PASSWORD="abcd-efgh-ijkl-mnop"
#        export SYS_TEAM_ID="ABCDEF1234"
#        export SYS_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDEF1234)"
#
#   5. Optional overrides:
#
#        export SYS_VERSION="1.2.3"        # auto-detected from Info.plist
#        export SYS_BUNDLE_ID="com.sysmon.app"
#        export SYS_OUTPUT_DIR="./dist"    # where .dmg and .rb are written
#
# ==============================================================================
#  USAGE
# ==============================================================================
#
#   export SYS_APPLE_ID="you@example.com"
#   export SYS_APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export SYS_TEAM_ID="ABCDEF1234"
#   export SYS_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDEF1234)"
#   ./scripts/deploy_brew.sh
#
# ==============================================================================

set -euo pipefail

# ---------- Configurable settings (override via environment) ----------
APP_NAME="${APP_NAME:-sysmon}"
WIDGET_NAME="${WIDGET_NAME:-sysmonWidget}"
BUNDLE_ID="${SYS_BUNDLE_ID:-com.sysmon.app}"
WIDGET_BUNDLE_ID="${BUNDLE_ID}.widget"
APP_GROUP="${SYS_APP_GROUP:-group.com.sysmon.shared}"
VERSION="${SYS_VERSION:-}"
OUTPUT_DIR="${SYS_OUTPUT_DIR:-dist}"
MIN_VERSION="13.0"

# Sensitive credentials (must be set in environment)
APPLE_ID="${SYS_APPLE_ID:-}"
APPLE_PASSWORD="${SYS_APPLE_PASSWORD:-}"
TEAM_ID="${SYS_TEAM_ID:-}"
SIGN_IDENTITY="${SYS_SIGN_IDENTITY:-}"

# --------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"
DMG_PATH="$BUILD_DIR/sysmon.dmg"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_step() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC}   $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC}  $1" >&2; }

# ==============================================================================
#  1. PRE-FLIGHT CHECKS
# ==============================================================================

preflight() {
    log_step "Running pre-flight checks..."

    # --- Required tools ---
    local missing=()
    for tool in swiftc xcrun codesign hdiutil security plutil sips iconutil; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_err "Missing required tools: ${missing[*]}"
        log_err "Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi
    log_info "All required tools found."

    # --- Detect version ---
    if [ -z "$VERSION" ]; then
        if [ -f "$PROJECT_DIR/sysmon/Info.plist" ]; then
            VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/sysmon/Info.plist" 2>/dev/null || true)
        fi
        if [ -z "$VERSION" ] && [ -f "$PROJECT_DIR/CHANGELOG.md" ]; then
            VERSION=$(grep -m1 '^## \[' "$PROJECT_DIR/CHANGELOG.md" | sed 's/## \[\(.*\)\].*/\1/' || true)
        fi
        if [ -z "$VERSION" ]; then
            VERSION="1.0.0"
            log_warn "Could not detect version. Defaulting to $VERSION"
        fi
    fi
    log_info "App version: $VERSION"

    # --- Credentials ---
    if [ -z "$APPLE_ID" ]; then
        log_err "SYS_APPLE_ID is not set. Export your Apple ID email."
        exit 1
    fi
    if [ -z "$APPLE_PASSWORD" ]; then
        log_err "SYS_APPLE_PASSWORD is not set. Export an app-specific password."
        exit 1
    fi
    if [ -z "$TEAM_ID" ]; then
        log_err "SYS_TEAM_ID is not set. Export your Apple Team ID."
        exit 1
    fi
    if [ -z "$SIGN_IDENTITY" ]; then
        log_err "SYS_SIGN_IDENTITY is not set."
        log_err "Find yours with: security find-identity -v -p basic | grep \"Developer ID\""
        exit 1
    fi

    # --- Verify signing identity exists in keychain ---
    if ! security find-identity -v -p basic | grep -qF "$SIGN_IDENTITY"; then
        log_err "Signing identity not found in keychain: $SIGN_IDENTITY"
        log_err "Check with: security find-identity -v -p basic | grep 'Developer ID'"
        exit 1
    fi
    log_info "Signing identity verified: $SIGN_IDENTITY"

    # --- Create output directories ---
    mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

    # --- SDK paths ---
    SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
    FRAMEWORKS="$SDK_PATH/System/Library/Frameworks"
    SWIFT_MODULES="$SDK_PATH/usr/lib/swift"
    log_info "SDK: $SDK_PATH"

    log_step "Pre-flight checks passed."
}

# ==============================================================================
#  2. COMPILE APP + WIDGET (swiftc)
# ==============================================================================

compile_app() {
    log_step "Compiling main app executable (swiftc)..."

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
        -o "$EXE_DIR/$APP_NAME" || {
            log_err "Main app compilation failed."
            exit 1
        }

    log_info "Main executable compiled: $EXE_DIR/$APP_NAME"
}

compile_widget() {
    log_step "Compiling Widget extension (swiftc)..."

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
        -o "$EXE_DIR/$WIDGET_NAME" || {
            log_err "Widget compilation failed."
            exit 1
        }

    log_info "Widget executable compiled: $EXE_DIR/$WIDGET_NAME"
}

# ==============================================================================
#  3. ASSEMBLE BUNDLE (Info.plist, icons, entitlements)
# ==============================================================================

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

create_app_plist() {
    log_step "Creating Info.plist files..."

    # Main app Info.plist
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
    <key>CFBundleVersion</key>                 <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>          <string>$MIN_VERSION</string>
    <key>LSUIElement</key>                     <true/>
</dict>
</plist>
EOF

    # Widget Info.plist
    local WPLIST="$WIDGET_BUNDLE/Contents/Info.plist"
    mkdir -p "$(dirname "$WPLIST")"
    cat > "$WPLIST" << EOF
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
    <key>CFBundleVersion</key>                 <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>          <string>$MIN_VERSION</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
EOF

    log_info "Info.plist files created."
}

create_entitlements() {
    log_step "Generating entitlements..."

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

# ==============================================================================
#  4. CODE SIGN
# ==============================================================================

sign_bundles() {
    log_step "Signing application bundles..."

    local ENT_APP="$BUILD_DIR/sysmon.entitlements"
    local ENT_WIDGET="$BUILD_DIR/sysmonWidget.entitlements"
    local CODESIGN_OPTS="--force --deep --options runtime --timestamp"

    # Sign widget extension first (innermost must be signed first)
    log_info "Signing widget extension..."
    codesign $CODESIGN_OPTS \
        --entitlements "$ENT_WIDGET" \
        --sign "$SIGN_IDENTITY" \
        "$WIDGET_BUNDLE" || {
            log_err "Widget signing failed."
            exit 1
        }
    log_info "Widget signed."

    # Sign main app
    log_info "Signing main app..."
    codesign $CODESIGN_OPTS \
        --entitlements "$ENT_APP" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE" || {
            log_err "App signing failed."
            exit 1
        }
    log_info "App signed."

    # Verify
    log_info "Verifying code signature..."
    codesign --verify --verbose=4 --deep --strict "$APP_BUNDLE" || {
        log_err "Code-sign verification FAILED."
        exit 1
    }
    log_step "Code sign verified."
}

# ==============================================================================
#  5. NOTARIZE .APP
# ==============================================================================

notarize_app() {
    log_step "Notarizing application..."

    local ZIP_PATH="$BUILD_DIR/sysmon_notarize.zip"

    log_info "Compressing app for notarization submission..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    log_info "Submitting to Apple Notary Service..."
    local SUBMIT_OUTPUT
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --output-format json 2>&1) || {
            log_err "Notarization submission failed:"
            echo "$SUBMIT_OUTPUT"
            exit 1
        }

    local STATUS
    STATUS=$(echo "$SUBMIT_OUTPUT" | jq -r '.status // "Unknown"' 2>/dev/null || echo "Unknown")
    log_info "Notarization status: $STATUS"

    if [ "$STATUS" != "Accepted" ]; then
        log_err "Notarization was NOT accepted."
        log_err "Raw output:"
        echo "$SUBMIT_OUTPUT" | jq . 2>/dev/null || echo "$SUBMIT_OUTPUT"
        exit 1
    fi

    log_info "Notarization accepted."

    log_info "Stapling notarization ticket to .app..."
    xcrun stapler staple "$APP_BUNDLE" || {
        log_warn "Stapling .app failed (non-fatal)."
    }

    rm -f "$ZIP_PATH"
    log_step "App notarized and stapled."
}

# ==============================================================================
#  6. CREATE DMG
# ==============================================================================

create_dmg() {
    log_step "Creating distribution DMG..."

    rm -f "$DMG_PATH"

    log_info "Building DMG with hdiutil (UDZO format)..."
    hdiutil create \
        -ov \
        -srcfolder "$APP_BUNDLE" \
        -volname "$APP_NAME" \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_PATH" || {
            log_err "hdiutil DMG creation failed."
            exit 1
        }

    log_step "DMG created: $DMG_PATH"
    log_info "DMG size: $(du -sh "$DMG_PATH" | cut -f1)"
}

# ==============================================================================
#  7. NOTARIZE DMG
# ==============================================================================

notarize_dmg() {
    log_step "Notarizing DMG..."

    log_info "Submitting DMG to Apple Notary Service..."
    local SUBMIT_OUTPUT
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        --output-format json 2>&1) || {
            log_err "DMG notarization submission failed:"
            echo "$SUBMIT_OUTPUT"
            exit 1
        }

    local STATUS
    STATUS=$(echo "$SUBMIT_OUTPUT" | jq -r '.status // "Unknown"' 2>/dev/null || echo "Unknown")
    log_info "DMG notarization status: $STATUS"

    if [ "$STATUS" != "Accepted" ]; then
        log_err "DMG notarization was NOT accepted."
        log_err "Raw output:"
        echo "$SUBMIT_OUTPUT" | jq . 2>/dev/null || echo "$SUBMIT_OUTPUT"
        exit 1
    fi

    log_info "DMG notarization accepted."

    log_info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH" || {
        log_err "Stapling DMG failed."
        exit 1
    }

    log_step "DMG notarized and stapled."
}

# ==============================================================================
#  8. GENERATE HOMEBREW CASK
# ==============================================================================

generate_cask() {
    log_step "Generating Homebrew Cask..."

    local FINAL_DMG="$OUTPUT_DIR/sysmon-${VERSION}.dmg"
    cp "$DMG_PATH" "$FINAL_DMG"
    log_info "Final DMG copied to: $FINAL_DMG"

    local SHA256
    SHA256=$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')
    log_info "SHA-256: $SHA256"

    local CASK_FILE="$OUTPUT_DIR/sysmon.rb"

    cat > "$CASK_FILE" << RUBY_EOF
cask "sysmon" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/YOUR_GITHUB_USER/homebrew-sysmon/releases/download/v#{version}/sysmon-#{version}.dmg",
      verified: "github.com/YOUR_GITHUB_USER/homebrew-sysmon/"
  name "sysmon"
  desc "Lightweight macOS menu bar system monitor with WidgetKit integration"
  homepage "https://github.com/YOUR_GITHUB_USER/sysmon"

  # depends_on macos: ">= :ventura"

  app "sysmon.app"

  zap trash: [
    "~/Library/Application Scripts/$APP_GROUP",
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Caches/$BUNDLE_ID",
    "~/Library/Containers/$BUNDLE_ID",
    "~/Library/Containers/$WIDGET_BUNDLE_ID",
    "~/Library/Group Containers/$APP_GROUP",
    "~/Library/HTTPStorages/$BUNDLE_ID",
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
    "~/Library/WebKit/$BUNDLE_ID",
  ]
end
RUBY_EOF

    log_step "Homebrew Cask generated: $CASK_FILE"

    # ==================== PRINT SUMMARY ====================
    echo ""
    echo "============================================================================="
    echo "  DEPLOYMENT COMPLETE"
    echo "============================================================================="
    echo ""
    echo "  Version:     $VERSION"
    echo "  DMG:         $FINAL_DMG"
    echo "  SHA-256:     $SHA256"
    echo "  Cask:        $CASK_FILE"
    echo ""
    echo "  Homebrew Cask (sysmon.rb):"
    echo "  ----------------------------------------------------------"
    echo ""
    cat "$CASK_FILE"
    echo ""
    echo "  ----------------------------------------------------------"
    echo ""
    echo "  NEXT STEPS:"
    echo "  -----------"
    echo "  1. Create the homebrew-sysmon GitHub repo:"
    echo "     https://github.com/new"
    echo "     Repository name: homebrew-sysmon"
    echo "     Description: Homebrew Tap for sysmon"
    echo ""
    echo "  2. Clone it and add the Cask:"
    echo "     git clone git@github.com:YOUR_GITHUB_USER/homebrew-sysmon.git"
    echo "     cd homebrew-sysmon"
    echo "     mkdir -p Casks"
    echo "     cp ${CASK_FILE} Casks/sysmon.rb"
    echo ""
    echo "  3. Create a GitHub Release in the Tap repo with the DMG attached:"
    echo "     gh release create v${VERSION} ${FINAL_DMG} --title 'sysmon v${VERSION}'"
    echo ""
    echo "  4. Commit & push the Cask:"
    echo "     git add Casks/sysmon.rb"
    echo "     git commit -m 'Add sysmon v${VERSION}'"
    echo "     git push origin main"
    echo ""
    echo "  5. Users can then install with:"
    echo "     brew tap YOUR_GITHUB_USER/sysmon"
    echo "     brew install --cask sysmon"
    echo ""
    echo "============================================================================="
}

# ==================== MAIN ====================

main() {
    echo ""
    echo "============================================================================="
    echo "  sysmon — Homebrew Cask Deployer (swiftc / no Xcode)"
    echo "============================================================================="
    echo ""

    preflight
    compile_app
    compile_widget
    create_app_icon
    create_app_plist
    create_entitlements
    sign_bundles
    notarize_app
    create_dmg
    notarize_dmg
    generate_cask

    echo ""
    log_step "All done! sysmon v${VERSION} deployed successfully."
    echo ""
}

main "$@"
