#!/usr/bin/env bash
# ================================================================
#  sysmon — GitHub Release script
# ================================================================
#  Usage:
#    ./scripts/release.sh 1.0.0
#
#  Requires:
#    - GitHub CLI (brew install gh) and authenticated (gh auth login)
#    - A built DMG at build/sysmon-latest.dmg
#      (run ./scripts/build_from_source.sh first, optionally with
#       SYS_SIGN_IDENTITY set for a signed release)
#
#  What it does:
#    1. Creates an annotated git tag matching the version
#    2. Pushes the tag to origin
#    3. Creates a GitHub Release with release notes from CHANGELOG.md
#       (or a default message if none exists)
#    4. Uploads the DMG as a release asset
# ================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log_step() { echo -e "${GREEN}[RELEASE]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC}   $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC}  $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Pre-flight checks ----------
VERSION="${1:-}"

# Fall back to VERSION file (single source of truth) if no argument given
if [ -z "$VERSION" ]; then
    VERSION_FILE="$PROJECT_DIR/VERSION"
    if [ -f "$VERSION_FILE" ]; then
        VERSION="$(head -1 "$VERSION_FILE" | tr -d '[:space:]')"
        log_info "Version auto-detected from VERSION file: $VERSION"
    else
        log_err "Usage: $0 <version>"
        log_err "Example: $0 1.0.0"
        log_err "Or create a VERSION file in the project root."
        exit 1
    fi
fi

if ! command -v gh &>/dev/null; then
    log_err "GitHub CLI (gh) not found. Install it: brew install gh"
    log_err "Then authenticate: gh auth login"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    log_err "GitHub CLI not authenticated. Run: gh auth login"
    exit 1
fi
DMG_PATH="$PROJECT_DIR/build/sysmon-latest.dmg"

if [ ! -f "$DMG_PATH" ]; then
    log_err "DMG not found at $DMG_PATH"
    log_err "Run ./scripts/build_from_source.sh first."
    exit 1
fi

# ---------- Git tag ----------
TAG="v${VERSION}"

log_step "Creating annotated tag $TAG ..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
    log_info "Tag $TAG already exists, skipping tag creation."
else
    git tag -a "$TAG" -m "sysmon v${VERSION}"
    git push origin "$TAG"
    log_info "Tag $TAG pushed to origin."
fi

# ---------- Release notes ----------
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
    # Extract the section for this version from the changelog
    NOTES=$(awk "/^## \[${VERSION}\]/{flag=1; next} /^## \[/{flag=0} flag" "$CHANGELOG")
    if [ -z "$NOTES" ]; then
        NOTES="sysmon v${VERSION} — Menu Bar system monitor with WidgetKit widget."
    fi
else
    NOTES=$(cat << EOF
sysmon v${VERSION} — Menu Bar system monitor with WidgetKit widget.

### Features
- Real-time CPU and Memory stats in the macOS menu bar
- Notification Center widget (Small + Medium families)
- Sandbox-compatible — uses only public host_statistics / sysctl APIs
- No Xcode required to build — pure swiftc + shell
EOF
)
fi

# ---------- Create release ----------
log_step "Creating GitHub Release $TAG ..."
gh release create "$TAG" \
    --title "sysmon v${VERSION}" \
    --notes "$NOTES" \
    --prerelease=false

# ---------- Upload DMG ----------
log_step "Uploading DMG asset..."
gh release upload "$TAG" "$DMG_PATH" --clobber

log_step "Release $TAG published successfully!"
echo ""
echo "  Release URL: $(gh release view "$TAG" --json url -q .url)"
echo "  DMG asset:   sysmon-latest.dmg (attached)"