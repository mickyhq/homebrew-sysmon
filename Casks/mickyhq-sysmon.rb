cask "mickyhq-sysmon" do
  version "1.0"
  sha256 "675d3c7ee5bfd5bd33cf03ad075b7f383d35dd7a7ff2ff402cd762f9d11d428f"

  url "https://github.com/mickyhq/homebrew-sysmon/releases/download/v#{version}/sysmon-#{version}.dmg",
      verified: "github.com/mickyhq/homebrew-sysmon/"
  name "sysmon"
  desc "Lightweight menu bar system monitor with WidgetKit CPU/Memory widget"
  homepage "https://github.com/mickyhq/homebrew-sysmon"

  depends_on macos: :ventura
  depends_on arch: :arm64

  auto_updates true

  app "sysmon.app"

  uninstall delete: [
    "~/Library/Application Scripts/group.com.sysmon.shared",
    "~/Library/Group Containers/group.com.sysmon.shared",
  ]

  zap trash: [
    "~/Library/Application Support/sysmon",
    "~/Library/Caches/com.sysmon.app",
    "~/Library/Containers/com.sysmon.app",
    "~/Library/Containers/com.sysmon.app.widget",
    "~/Library/HTTPStorages/com.sysmon.app",
    "~/Library/Preferences/com.sysmon.app.plist",
    "~/Library/Saved Application State/com.sysmon.app.savedState",
    "~/Library/WebKit/com.sysmon.app",
  ]

  caveats <<~EOS
    sysmon runs in the menu bar only — there is no Dock icon.
    If the menu bar text doesn't appear, you may need to allow
    sysmon in System Settings → Privacy & Security.

    To add the CPU/Memory widget, open Notification Center and
    click "Edit Widgets" at the bottom.
  EOS

  livecheck do
    url "https://github.com/mickyhq/homebrew-sysmon/releases.atom"
    strategy :page_match
    regex(%r{<id>.*/releases/tag/v?(\d+(?:\.\d+)+)</id>}i)
  end
end
