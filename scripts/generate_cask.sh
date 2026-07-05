#!/usr/bin/env bash
# ==============================================================================
#  sysmon — Homebrew Cask Generator
# ==============================================================================
#  Takes an already-built, notarized sysmon.dmg and produces:
#    - SHA-256 checksum
#    - mickyhq-sysmon.rb   (Homebrew Cask, ready to commit to your Tap repo)
#
#  No compilation, signing, or notarization is performed. This script
#  assumes the DMG is already production-ready.
#
# ==============================================================================
#  USAGE
# ==============================================================================
#
#   ./scripts/generate_cask.sh [path/to/sysmon.dmg] [version]
#
#   Examples:
#
#     # Auto-detect DMG in dist/ or build/, auto-detect version from Info.plist
#     ./scripts/generate_cask.sh
#
#     # Explicit DMG path and version
#     ./scripts/generate_cask.sh dist/sysmon-1.0.0.dmg 1.0.0
#
#   Optional environment variables:
#
#     SYS_GITHUB_USER="yourusername"   # defaults to "mickyhq"
#     SYS_BUNDLE_ID="com.sysmon.app"   # bundle identifier for zap paths
#     SYS_OUTPUT_DIR="./Casks"         # where mickyhq-sysmon.rb is written
#
# ==============================================================================
#  HOME-BREW TAP REPOSITORY STRUCTURE
# ==============================================================================
#
#  Your Tap repository (homebrew-sysmon) must look like this:
#
#    homebrew-sysmon/
#    └── Casks/
#        └── mickyhq-sysmon.rb    <-- this generated file
#
#  Place mickyhq-sysmon.rb inside the Casks/ directory, commit, and push.
#  Users then install with:
#
#    brew install --cask mickyhq/sysmon/mickyhq-sysmon
#
#  The DMG must be uploaded as a GitHub Release asset in the Tap repo:
#
#    https://github.com/mickyhq/homebrew-sysmon/releases
#
#  The Cask's url field points to that release asset.
# ==============================================================================

set -euo pipefail

# ---------- Configurable settings ----------
APP_NAME="sysmon"
BUNDLE_ID="${SYS_BUNDLE_ID:-com.sysmon.app}"
WIDGET_BUNDLE_ID="${BUNDLE_ID}.widget"
APP_GROUP="${SYS_APP_GROUP:-group.com.sysmon.shared}"
GITHUB_USER="${SYS_GITHUB_USER:-mickyhq}"
OUTPUT_DIR="${SYS_OUTPUT_DIR:-Casks}"
VERSION="${2:-}"   # optional second positional argument

# ---------- Paths ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Colors ----------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step() { echo -e "${GREEN}[CASK]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ==============================================================================
#  1. LOCATE THE DMG
# ==============================================================================

find_dmg() {
    log_step "Locating sysmon.dmg..."

    local dmg="${1:-}"

    if [ -n "$dmg" ] && [ -f "$dmg" ]; then
        DMG_PATH="$(cd "$(dirname "$dmg")" 2>/dev/null && pwd)/$(basename "$dmg")"
        log_info "Using explicit DMG: $DMG_PATH"
        return
    fi

    if [ -n "$dmg" ]; then
        log_err "Specified DMG not found: $dmg"
        exit 1
    fi

    # Auto-discovery: check known locations
    local candidates=(
        "$PROJECT_DIR/build/sysmon.dmg"
        "$PROJECT_DIR/build/sysmon-latest.dmg"
        "$PROJECT_DIR/dist/sysmon.dmg"
        "$PROJECT_DIR/dist/sysmon-latest.dmg"
    )

    # Also check for versioned DMGs in dist/
    if [ -d "$PROJECT_DIR/dist" ]; then
        local versioned
        versioned=$(find "$PROJECT_DIR/dist" -maxdepth 1 -name "sysmon-*.dmg" -type f 2>/dev/null | sort -r | head -1)
        if [ -n "$versioned" ]; then
            candidates+=("$versioned")
        fi
    fi

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            DMG_PATH="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd)/$(basename "$candidate")"
            log_info "Auto-detected DMG: $DMG_PATH"
            return
        fi
    done

    log_err "No sysmon.dmg found. Build the DMG first, or provide an explicit path:"
    log_err "  $0 path/to/sysmon.dmg [version]"
    exit 1
}

# ==============================================================================
#  2. DETECT VERSION
# ==============================================================================

find_version() {
    log_step "Detecting version..."

    if [ -n "$VERSION" ]; then
        log_info "Using explicit version: $VERSION"
        return
    fi

    # Try VERSION file (single source of truth)
    if [ -f "$PROJECT_DIR/VERSION" ]; then
        VERSION=$(head -1 "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
    fi

    # Fallback to Info.plist
    if [ -z "$VERSION" ] && [ -f "$PROJECT_DIR/sysmon/Info.plist" ]; then
        VERSION=$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/sysmon/Info.plist" 2>/dev/null || true)
    fi

    # Fallback to CHANGELOG.md
    if [ -z "$VERSION" ] && [ -f "$PROJECT_DIR/CHANGELOG.md" ]; then
        VERSION=$(grep -m1 '^## \[' "$PROJECT_DIR/CHANGELOG.md" 2>/dev/null | sed 's/## \[\(.*\)\].*/\1/' || true)
    fi

    # Hard fallback
    if [ -z "$VERSION" ]; then
        VERSION="1.0.0"
        log_warn "Could not auto-detect version; defaulting to $VERSION"
    else
        log_info "Detected version: $VERSION"
    fi
}

# ==============================================================================
#  3. COMPUTE SHA-256
# ==============================================================================

compute_sha256() {
    log_step "Computing SHA-256 checksum..."

    if ! command -v shasum &>/dev/null; then
        log_err "shasum not found. Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    local raw
    raw=$(shasum -a 256 "$DMG_PATH")

    # Strip the filename, leaving only the 64-character hex digest
    SHA256=$(echo "$raw" | awk '{print $1}')

    # Validate: must look like exactly 64 lowercase hex characters
    if [[ ! "$SHA256" =~ ^[a-f0-9]{64}$ ]]; then
        log_err "SHA-256 output does not look like a valid 64-char hex digest:"
        log_err "  Raw output: $raw"
        log_err "  Parsed hash: $SHA256"
        exit 1
    fi

    log_info "SHA-256: $SHA256"

    local dmg_size
    dmg_size=$(du -sh "$DMG_PATH" | cut -f1)
    log_info "DMG size: $dmg_size"
}

# ==============================================================================
#  4. GENERATE THE RUBY CASK
# ==============================================================================

generate_cask() {
    log_step "Generating Homebrew Cask: mickyhq-sysmon.rb..."

    mkdir -p "$OUTPUT_DIR"
    local CASK_FILE="$OUTPUT_DIR/mickyhq-sysmon.rb"

    cat > "$CASK_FILE" << 'RUBY_EOF'
cask "mickyhq-sysmon" do
  version "%VERSION%"
  sha256 "%SHA256%"

  url "https://github.com/%GITHUB_USER%/homebrew-sysmon/releases/download/v#{version}/sysmon-#{version}.dmg",
      verified: "github.com/%GITHUB_USER%/homebrew-sysmon/"
  name "sysmon"
  desc "Lightweight menu bar system monitor with WidgetKit CPU/Memory widget"
  homepage "https://github.com/%GITHUB_USER%/homebrew-sysmon"

  depends_on macos: :ventura
  depends_on arch: :arm64

  auto_updates true

  app "sysmon.app"

  uninstall delete: [
    "~/Library/Application Scripts/%APP_GROUP%",
    "~/Library/Group Containers/%APP_GROUP%",
  ]

  zap trash: [
    "~/Library/Application Support/%APP_NAME%",
    "~/Library/Caches/%BUNDLE_ID%",
    "~/Library/Containers/%BUNDLE_ID%",
    "~/Library/Containers/%WIDGET_BUNDLE_ID%",
    "~/Library/HTTPStorages/%BUNDLE_ID%",
    "~/Library/Preferences/%BUNDLE_ID%.plist",
    "~/Library/Saved Application State/%BUNDLE_ID%.savedState",
    "~/Library/WebKit/%BUNDLE_ID%",
  ]

  caveats <<~EOS
    sysmon runs in the menu bar only — there is no Dock icon.
    If the menu bar text doesn't appear, you may need to allow
    sysmon in System Settings → Privacy & Security.

    To add the CPU/Memory widget, open Notification Center and
    click "Edit Widgets" at the bottom.
  EOS

  livecheck do
    url "https://github.com/%GITHUB_USER%/homebrew-sysmon/releases.atom"
    strategy :page_match
    regex(%r{<id>.*/releases/tag/v?(\d+(?:\.\d+)+)</id>}i)
  end
end
RUBY_EOF

    # Replace placeholders with actual values
    sed -i '' \
        -e "s|%VERSION%|${VERSION}|g" \
        -e "s|%SHA256%|${SHA256}|g" \
        -e "s|%GITHUB_USER%|${GITHUB_USER}|g" \
        -e "s|%BUNDLE_ID%|${BUNDLE_ID}|g" \
        -e "s|%APP_NAME%|${APP_NAME}|g" \
        -e "s|%WIDGET_BUNDLE_ID%|${WIDGET_BUNDLE_ID}|g" \
        -e "s|%APP_GROUP%|${APP_GROUP}|g" \
        "$CASK_FILE"

    log_step "Cask written: $CASK_FILE"
}

# ==============================================================================
#  5. PRINT SUMMARY
# ==============================================================================

print_summary() {
    local CASK_FILE="$OUTPUT_DIR/mickyhq-sysmon.rb"

    echo ""
    echo "============================================================================="
    echo "  HOMEBREW CASK GENERATED"
    echo "============================================================================="
    echo ""
    echo "  DMG:         $DMG_PATH"
    echo "  Version:     $VERSION"
    echo "  SHA-256:     $SHA256"
    echo "  Cask:        $CASK_FILE"
    echo ""
    echo "  ── Cask preview ──────────────────────────────────────────────────────────"
    echo ""
    cat "$CASK_FILE"
    echo ""
    echo "  ───────────────────────────────────────────────────────────────────────────"
    echo ""
    echo "  HOW TO DEPLOY TO YOUR HOMEBREW TAP"
    echo "  ==================================="
    echo ""
    echo "  1. Create the Tap repository on GitHub:"
    echo "     https://github.com/new"
    echo "     Repository name: homebrew-sysmon"
    echo "     Description:          Homebrew Tap for sysmon"
    echo "     Visibility:           Public"
    echo ""
    echo "  2. Clone the Tap repo:"
    echo "     git clone git@github.com:${GITHUB_USER}/homebrew-sysmon.git"
    echo "     cd homebrew-sysmon"
    echo ""
    echo "  3. Create the required directory and copy the Cask:"
    echo "     mkdir -p Casks"
    echo "     cp ${CASK_FILE} Casks/mickyhq-sysmon.rb"
    echo ""
    echo "  4. Upload the DMG as a GitHub Release asset (IMPORTANT):"
    echo "     cd homebrew-sysmon"
    echo "     gh release create v${VERSION} ${DMG_PATH} --title \"sysmon v${VERSION}\""
    echo ""
    echo "     If you don't have gh, create the release manually at:"
    echo "     https://github.com/${GITHUB_USER}/homebrew-sysmon/releases/new"
    echo "     Tag:          v${VERSION}"
    echo "     Attach file:  ${DMG_PATH}"
    echo ""
    echo "  5. Commit and push the Cask:"
    echo "     git add Casks/mickyhq-sysmon.rb"
    echo "     git commit -m \"Add sysmon v${VERSION}\""
    echo "     git push origin main"
    echo ""
    echo "  6. Users install with:"
    echo "     brew tap ${GITHUB_USER}/sysmon"
    echo "     brew install --cask ${GITHUB_USER}/sysmon/mickyhq-sysmon"
    echo ""
    echo "     Or to uninstall completely (zaps all app data):"
    echo "     brew uninstall --cask --zap mickyhq-sysmon"
    echo ""
    echo "  REPOSITORY LAYOUT"
    echo "  ================="
    echo ""
    echo "  homebrew-sysmon/          ← GitHub repository ${GITHUB_USER}/homebrew-sysmon"
    echo "  ├── Casks/"
    echo "  │   └── mickyhq-sysmon.rb ← The generated Cask (place it here)"
    echo "  └── README.md             ← Optional"
    echo ""
    echo "  Releases (on GitHub, not in the repo itself):"
    echo "    v${VERSION}"
    echo "    └── sysmon-${VERSION}.dmg   ← The DMG asset (rename before attaching)"
    echo ""
    echo "  IMPORTANT: The DMG filename in the release MUST match what the Cask"
    echo "  expects:  sysmon-${VERSION}.dmg"
    echo ""
    echo "  To rename before attaching to the release:"
    echo "    cp ${DMG_PATH} /tmp/sysmon-${VERSION}.dmg"
    echo "    gh release create v${VERSION} /tmp/sysmon-${VERSION}.dmg --title \"sysmon v${VERSION}\""
    echo ""
    echo "============================================================================="
}

# ==================== MAIN ====================

main() {
    local dmg_arg="${1:-}"

    echo ""
    echo "============================================================================="
    echo "  sysmon — Homebrew Cask Generator"
    echo "============================================================================="
    echo ""

    find_dmg "$dmg_arg"
    find_version
    compute_sha256
    generate_cask
    print_summary
}

main "$@"
