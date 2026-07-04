#!/bin/bash
# Stop immediately if any command fails
set -e

TAP_NAME="mickyhq/sysmon"
CASK_NAME="mickyhq/sysmon/sysmon"

echo "🧼 Step 1: Cleaning up local Homebrew environment variables..."
# Direct Homebrew to evaluate the local Git files directly instead of the remote centralized JSON index
export HOMEBREW_NO_INSTALL_FROM_API=1

echo "🗑️ Step 2: Wiping existing tap configurations & caches..."
# Remove any bad local state for the tap
brew untap "$TAP_NAME" || true

echo "🔄 Step 3: Refetching your repository from GitHub..."
# Perform a clean checkout to download the Casks/sysmon.rb file
brew tap "$TAP_NAME"

echo "🧐 Step 4: Forcing a local database update..."
brew update

echo "🛡️ Step 5: Auditing the cask file syntax..."
echo "--------------------------------------------------------"
if brew audit --cask "$CASK_NAME"; then
    echo "✅ No Ruby syntax or formatting issues detected in sysmon.rb!"
else
    echo "❌ Homebrew discovered a formatting validation error in your file."
fi
echo "--------------------------------------------------------"

echo "🔍 Step 6: Searching for your package..."
brew search "$CASK_NAME"

echo ""
echo "🚀 Diagnostics Complete! If Step 6 displayed your package, try running:"
echo "   brew install --cask $CASK_NAME"