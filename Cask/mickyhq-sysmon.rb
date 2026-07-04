cask "mickyhq-sysmon" do
  version "1.0"
  sha256 "174eb725a805b20d374efc0b5810e64383a8f7efa6362cf9f6dc97c2a90f5763"

  url "https://github.com/mickyhq/homebrew-sysmon/releases/download/v#{version}/sysmon-1.0.dmg",
      verified: "github.com/mickyhq/homebrew-sysmon/"
  name "sysmon"
  desc "Lightweight macOS menu bar system monitor with WidgetKit CPU/Memory widget"
  homepage "https://github.com/mickyhq/sysmon"
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
