#!/usr/bin/env bash
# ==============================================================================
#  sysmon — Homebrew Tap Release Script
# ==============================================================================
#  Uploads the DMG as a GitHub Release asset in your homebrew-sysmon Tap repo.
#  The DMG is renamed to match the Cask's expected filename: sysmon-<version>.dmg
#
# ==============================================================================
#  USAGE
# ==============================================================================
#
#   ./scripts/release_tap.sh [version] [dmg_path]
#
#   Examples:
#     ./scripts/release_tap.sh 1.0
#     ./scripts/release_tap.sh 1.0 build/sysmon-latest.dmg
#
#   Optional environment variables:
#     SYS_TAP_REPO="mickyhq/homebrew-sysmon"   # Tap repo (owner/name)
#     SYS_GITHUB_USER="mickyhq"                # GitHub username
#
# ==============================================================================
#  PREREQUISITES
# ==============================================================================
#
#   - GitHub CLI installed and authenticated: brew install gh && gh auth login
#   - A built DMG at build/sysmon-latest.dmg (run ./scripts/build_from_source.sh)
#
# ==============================================================================

set -euo pipefail

# ---------- Configurable settings ----------
APP_NAME="sysmon"
GITHUB_USER="${SYS_GITHUB_USER:-mickyhq}"
TAP_REPO="${SYS_TAP_REPO:-${GITHUB_USER}/homebrew-sysmon}"
VERSION="${1:-}"
DMG_INPUT="${2:-build/sysmon-latest.dmg}"

# ---------- Paths ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Colors ----------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_step() { echo -e "${GREEN}[TAP]${NC}  $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------- Pre-flight ----------

if [ -z "$VERSION" ]; then
    log_err "Usage: $0 <version> [dmg_path]"
    log_err "Example: $0 1.0"
    exit 1
fi

if ! command -v gh &>/dev/null; then
    log_err "GitHub CLI not found. Install: brew install gh"
    log_err "Then authenticate: gh auth login"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    log_err "GitHub CLI not authenticated. Run: gh auth login"
    exit 1
fi

# Resolve DMG path (relative to project dir if needed)
if [ ! -f "$DMG_INPUT" ]; then
    DMG_INPUT="$PROJECT_DIR/$DMG_INPUT"
fi

if [ ! -f "$DMG_INPUT" ]; then
    log_err "DMG not found at: $DMG_INPUT"
    log_err "Run ./scripts/build_from_source.sh first."
    exit 1
fi

# ---------- Rename DMG ----------
TAG="v${VERSION}"
DMG_OUTPUT="/tmp/sysmon-${VERSION}.dmg"

log_step "Copying DMG: $DMG_INPUT → $DMG_OUTPUT"
cp "$DMG_INPUT" "$DMG_OUTPUT"
log_info "Renamed DMG ready: $DMG_OUTPUT ($(du -sh "$DMG_OUTPUT" | cut -f1))"

# ---------- Create GitHub Release in Tap repo ----------
log_step "Creating release $TAG in $TAP_REPO ..."

gh release create "$TAG" \
    "$DMG_OUTPUT" \
    --repo "$TAP_REPO" \
    --title "sysmon v${VERSION}" \
    --notes "sysmon v${VERSION} — Notarized DMG for Homebrew Cask installation." \
    --prerelease=false || {
        log_err "Release creation failed."
        exit 1
    }

# ---------- Cleanup ----------
rm -f "$DMG_OUTPUT"

# ---------- Summary ----------
echo ""
echo "============================================================================="
echo "  TAP RELEASE PUBLISHED"
echo "============================================================================="
echo ""
echo "  Tap repo:    $TAP_REPO"
echo "  Tag:         $TAG"
echo "  DMG asset:   sysmon-${VERSION}.dmg"
echo "  Release URL: https://github.com/${TAP_REPO}/releases/tag/${TAG}"
echo ""
echo "  Cask url now resolves to:"
echo "  https://github.com/${TAP_REPO}/releases/download/${TAG}/sysmon-${VERSION}.dmg"
echo ""
echo "  Next: update the Cask checksum, then commit and push:"
echo "    ./scripts/generate_cask.sh build/sysmon-latest.dmg ${VERSION}"
echo "    git add Casks/mickyhq-sysmon.rb"
echo "    git commit -m 'Update mickyhq-sysmon to v${VERSION}' && git push"
echo ""
echo "============================================================================="
