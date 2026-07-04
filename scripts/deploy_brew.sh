#!/usr/bin/env bash
# ==============================================================================
#  sysmon — Homebrew Cask Deployment Script
# ==============================================================================
#  This script automates the complete macOS deployment pipeline:
#
#    1. Build & Archive   — xcodebuild archive (Release)
#    2. Extract .app      — export from archive
#    3. Code Sign         — Developer ID Application certificate
#    4. Notarize .app     — Apple Notary service, staple ticket
#    5. Package DMG       — hdiutil (UDZO read-only compressed)
#    6. Notarize DMG      — Notarize + staple the final .dmg
#    7. Homebrew Cask     — Print the Ruby Cask block + SHA-256
#
# ==============================================================================
#  PREREQUISITES
# ==============================================================================
#
#   1. Xcode 15+ with command-line tools installed.
#
#   2. A valid Apple Developer ID Application certificate in your keychain.
#      Verify with: security find-identity -v -p basic | grep "Developer ID"
#
#   3. An App-Specific Password for notarization (generate at appleid.apple.com).
#
#   4. Required environment variables (set before running):
#
#        export SYS_APPLE_ID="you@example.com"
#        export SYS_APPLE_PASSWORD="abcd-efgh-ijkl-mnop"
#        export SYS_TEAM_ID="ABCDEF1234"
#        export SYS_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDEF1234)"
#
#   5. Optional overrides:
#
#        export SYS_VERSION="1.2.3"          # auto-detected if not set
#        export SYS_BUNDLE_ID="com.sysmon.app"
#        export SYS_PROJECT="sysmon.xcodeproj"
#        export SYS_SCHEME="sysmon"
#        export SYS_OUTPUT_DIR="./dist"       # where .dmg and .rb are written
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
PROJECT="${SYS_PROJECT:-sysmon.xcodeproj}"
SCHEME="${SYS_SCHEME:-sysmon}"
DERIVED_DATA="${SYS_DERIVED_DATA:-build/DerivedData}"
OUTPUT_DIR="${SYS_OUTPUT_DIR:-dist}"
ARCHIVE_PATH="${SYS_ARCHIVE_PATH:-build/sysmon.xcarchive}"

# Sensitive credentials (must be set in environment)
APPLE_ID="${SYS_APPLE_ID:-}"
APPLE_PASSWORD="${SYS_APPLE_PASSWORD:-}"
TEAM_ID="${SYS_TEAM_ID:-}"
SIGN_IDENTITY="${SYS_SIGN_IDENTITY:-}"

# --------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# ==================== PRE-FLIGHT CHECKS ====================

preflight() {
    log_step "Running pre-flight checks..."

    # --- Required tools ---
    local missing=()
    for tool in xcodebuild xcrun codesign hdiutil security plutil; do
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

    # --- Xcode project ---
    if [ ! -d "$PROJECT_DIR/$PROJECT" ] && [ ! -f "$PROJECT_DIR/$PROJECT/contents.xcworkspacedata" ]; then
        # The project may be a .xcodeproj directory or the scheme may be autodiscovered
        if [ ! -d "$PROJECT_DIR/$PROJECT" ]; then
            log_warn "Xcode project not found at $PROJECT_DIR/$PROJECT"
            log_warn "Attempting workspace / scheme autodiscovery..."
            # Try to find any .xcworkspace or .xcodeproj
            local found
            found=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null | head -1)
            if [ -z "$found" ]; then
                log_err "No Xcode project or workspace found in $PROJECT_DIR."
                log_err "Set SYS_PROJECT and SYS_SCHEME environment variables."
                exit 1
            fi
            PROJECT="$(basename "$found")"
            log_info "Auto-detected project: $PROJECT"
        fi
    fi

    # --- Detect version ---
    if [ -z "$VERSION" ]; then
        # Try Info.plist first
        if [ -f "$PROJECT_DIR/sysmon/Info.plist" ]; then
            VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/sysmon/Info.plist" 2>/dev/null || true)
        fi
        # Fallback to CHANGELOG.md
        if [ -z "$VERSION" ] && [ -f "$PROJECT_DIR/CHANGELOG.md" ]; then
            VERSION=$(grep -m1 '^## \[' "$PROJECT_DIR/CHANGELOG.md" | sed 's/## \[\(.*\)\].*/\1/' || true)
        fi
        # Hard fallback
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
    mkdir -p "$OUTPUT_DIR" "build"

    log_step "Pre-flight checks passed."
}

# ==================== 1. BUILD & ARCHIVE ====================

build_archive() {
    log_step "Building and archiving with xcodebuild..."

    # Clean derived data for a fresh build
    log_info "Cleaning derived data..."
    rm -rf "$DERIVED_DATA"

    # Clean build folder
    log_info "Cleaning build folder..."
    xcodebuild clean \
        -project "$PROJECT_DIR/$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        >/dev/null 2>&1 || {
            log_warn "xcodebuild clean returned non-zero; continuing..."
        }

    # Archive
    log_info "Archiving ($SCHEME, Release)..."
    xcodebuild archive \
        -project "$PROJECT_DIR/$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp" \
        | sed 's/^/  /' || {
            log_err "Archive failed. Check the xcodebuild output above."
            exit 1
        }

    log_step "Archive created: $ARCHIVE_PATH"
}

# ==================== 2. EXTRACT .APP ====================

extract_app() {
    log_step "Extracting .app from archive..."

    local EXPORT_PLIST="$PROJECT_DIR/build/exportOptions.plist"
    local EXPORT_DIR="$PROJECT_DIR/build/exported"

    # Create a minimal exportOptions.plist for Developer ID export
    cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

    log_info "Exporting with exportOptions.plist (developer-id method)..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        | sed 's/^/  /' || {
            log_err "Export failed."
            exit 1
        }

    APP_BUNDLE="$EXPORT_DIR/$APP_NAME.app"
    if [ ! -d "$APP_BUNDLE" ]; then
        log_err "Exported .app not found at: $APP_BUNDLE"
        exit 1
    fi

    log_step "App extracted: $APP_BUNDLE"
}

# ==================== 3. CODE SIGN ====================

sign_app() {
    log_step "Signing application bundle..."

    local ENTITLEMENTS_APP="$PROJECT_DIR/sysmon/sysmon.entitlements"
    local ENTITLEMENTS_WIDGET="$PROJECT_DIR/sysmonWidget/sysmonWidget.entitlements"
    local WIDGET_PLUGIN="$APP_BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"

    # If entitlements files don't exist (e.g., after xcodebuild they are embedded),
    # create a minimal one for re-signing
    if [ ! -f "$ENTITLEMENTS_APP" ]; then
        ENTITLEMENTS_APP="$PROJECT_DIR/build/sysmon.entitlements"
        mkdir -p "$PROJECT_DIR/build"
        cat > "$ENTITLEMENTS_APP" << EOF
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
        cat > "$PROJECT_DIR/build/sysmonWidget.entitlements" << EOF
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
        ENTITLEMENTS_WIDGET="$PROJECT_DIR/build/sysmonWidget.entitlements"
    fi

    # Sign widget extension first (innermost must be signed first)
    if [ -d "$WIDGET_PLUGIN" ]; then
        log_info "Signing Widget extension..."
        codesign --force --deep --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS_WIDGET" \
            --sign "$SIGN_IDENTITY" \
            "$WIDGET_PLUGIN" || {
                log_err "Widget signing failed."
                exit 1
            }
        log_info "Widget signed."
    else
        log_warn "Widget extension not found at $WIDGET_PLUGIN — skipping widget signing."
    fi

    # Sign main app
    log_info "Signing main app..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS_APP" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE" || {
            log_err "App signing failed."
            exit 1
        }

    # Verify
    log_info "Verifying code signature..."
    codesign --verify --verbose=4 --deep --strict "$APP_BUNDLE" || {
        log_err "Code-sign verification FAILED."
        exit 1
    }
    log_step "Code sign verified."
}

# ==================== 4. NOTARIZE .APP ====================

notarize_app() {
    log_step "Notarizing application..."

    local ZIP_PATH="$PROJECT_DIR/build/sysmon_notarize.zip"

    # Zip the app for notarization
    log_info "Compressing app for notarization submission..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    # Submit
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
        local REASON
        REASON=$(echo "$SUBMIT_OUTPUT" | jq -r '.issues[]?.message // "No details available"' 2>/dev/null)
        log_err "Notarization was NOT accepted."
        log_err "Reason: $REASON"
        log_err "Full output:"
        echo "$SUBMIT_OUTPUT" | jq . 2>/dev/null || echo "$SUBMIT_OUTPUT"
        exit 1
    fi

    log_info "Notarization accepted."

    # Staple the ticket to the app
    log_info "Stapling notarization ticket to .app..."
    xcrun stapler staple "$APP_BUNDLE" || {
        log_warn "Stapling .app failed (non-fatal). You may need to staple manually."
    }

    # Clean up zip
    rm -f "$ZIP_PATH"

    log_step "App notarized and stapled."
}

# ==================== 5. CREATE DMG ====================

create_dmg() {
    log_step "Creating distribution DMG..."

    local DMG_BUILD="$PROJECT_DIR/build/sysmon.dmg"

    # Remove old DMG if present
    rm -f "$DMG_BUILD"

    log_info "Building DMG with hdiutil (UDZO format)..."
    hdiutil create \
        -ov \
        -srcfolder "$APP_BUNDLE" \
        -volname "$APP_NAME" \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_BUILD" || {
            log_err "hdiutil DMG creation failed."
            exit 1
        }

    DMG_PATH="$DMG_BUILD"
    log_step "DMG created: $DMG_PATH"

    local DMG_SIZE
    DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
    log_info "DMG size: $DMG_SIZE"
}

# ==================== 6. NOTARIZE DMG ====================

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
        local REASON
        REASON=$(echo "$SUBMIT_OUTPUT" | jq -r '.issues[]?.message // "No details available"' 2>/dev/null)
        log_err "DMG notarization was NOT accepted."
        log_err "Reason: $REASON"
        log_err "Full output:"
        echo "$SUBMIT_OUTPUT" | jq . 2>/dev/null || echo "$SUBMIT_OUTPUT"
        exit 1
    fi

    log_info "DMG notarization accepted."

    # Staple the ticket to the DMG
    log_info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH" || {
        log_err "Stapling DMG failed."
        exit 1
    }

    log_step "DMG notarized and stapled."
}

# ==================== 7. GENERATE HOMEBREW CASK ====================

generate_cask() {
    log_step "Generating Homebrew Cask..."

    # Copy final DMG to output directory
    local FINAL_DMG="$OUTPUT_DIR/sysmon-$VERSION.dmg"
    cp "$DMG_PATH" "$FINAL_DMG"
    log_info "Final DMG copied to: $FINAL_DMG"

    # Calculate SHA-256
    local SHA256
    SHA256=$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')
    log_info "SHA-256: $SHA256"

    # Generate Cask file
    local CASK_FILE="$OUTPUT_DIR/sysmon.rb"
    local YEAR
    YEAR=$(date +%Y)

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
    echo "     ☑ Public"
    echo "     ☐ Add a README (optional)"
    echo ""
    echo "  2. Clone and create a release:"
    echo "     git clone git@github.com:YOUR_GITHUB_USER/homebrew-sysmon.git"
    echo "     cd homebrew-sysmon"
    echo "     mkdir -p Casks"
    echo "     cp ${CASK_FILE} Casks/sysmon.rb"
    echo ""
    echo "  3. Create a GitHub Release in the Tap repo:"
    echo "     gh release create v${VERSION} ${FINAL_DMG} --title 'sysmon v${VERSION}'"
    echo ""
    echo "  4. Commit and push the Cask:"
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
    echo "  sysmon — Homebrew Cask Deployer"
    echo "============================================================================="
    echo ""

    preflight
    build_archive
    extract_app
    sign_app
    notarize_app
    create_dmg
    notarize_dmg
    generate_cask

    echo ""
    log_step "All done! sysmon v${VERSION} deployed successfully."
    echo ""
}

main "$@"