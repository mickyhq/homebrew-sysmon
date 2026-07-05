#!/usr/bin/env bash

set -euo pipefail

TAP_NAME="${SYS_TAP_NAME:-mickyhq/sysmon}"
CASK_TOKEN="${SYS_CASK_TOKEN:-mickyhq-sysmon}"
CASK_NAME="${TAP_NAME}/${CASK_TOKEN}"

export HOMEBREW_NO_INSTALL_FROM_API=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_CACHE="${HOMEBREW_CACHE:-/tmp/homebrew-cache}"

if ! command -v brew &>/dev/null; then
    echo "brew not found" >&2
    exit 1
fi

if brew tap | grep -qx "$TAP_NAME"; then
    echo "Updating ${TAP_NAME}..."
    brew update
else
    echo "Tapping ${TAP_NAME}..."
    brew tap "$TAP_NAME"
fi

echo "Checking ${CASK_NAME}..."
brew audit --cask --strict "$CASK_NAME"

echo ""
echo "Verifying discoverability..."
echo "  brew search output:"
brew search "$CASK_TOKEN" 2>&1 || true
echo "  brew search ${TAP_NAME}/ output:"
brew search "${TAP_NAME}/" 2>&1 || true

brew info --cask "$CASK_NAME"

echo ""
echo "Brew deployment works."
echo "Install with:"
echo "  brew install --cask ${CASK_NAME}"
