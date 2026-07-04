cask "mickyhq-sysmon" do
  version "1.0"
  sha256 "675d3c7ee5bfd5bd33cf03ad075b7f383d35dd7a7ff2ff402cd762f9d11d428f"

  url "https://github.com/mickyhq/homebrew-sysmon/releases/download/v#{version}/sysmon-1.0.dmg",
      verified: "github.com/mickyhq/homebrew-sysmon/"
  name "sysmon"
  desc "Lightweight macOS menu bar system monitor with WidgetKit CPU/Memory widget"
  homepage "https://github.com/mickyhq/sysmon"

  # depends_on macos: ">= :ventura"

  app "sysmon.app"

  zap trash: [
    "~/Library/Application Scripts/group.com.sysmon.shared",
    "~/Library/Application Support/sysmon",
    "~/Library/Caches/com.sysmon.app",
    "~/Library/Containers/com.sysmon.app",
    "~/Library/Containers/com.sysmon.app.widget",
    "~/Library/Group Containers/group.com.sysmon.shared",
    "~/Library/HTTPStorages/com.sysmon.app",
    "~/Library/Preferences/com.sysmon.app.plist",
    "~/Library/Saved Application State/com.sysmon.app.savedState",
    "~/Library/WebKit/com.sysmon.app",
  ]
end
