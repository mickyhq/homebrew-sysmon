# sysmon — macOS System Monitor (Menu Bar + Widget)

sysmon is a lightweight, sandbox-compliant macOS application that displays
real-time **CPU** and **Memory** utilization in two locations:

1. **Menu Bar** — via SwiftUI's `MenuBarExtra` (macOS 13+)
2. **Notification Center Widget** — via WidgetKit

The app uses only public, approved C/Swift system APIs (`host_statistics`,
`host_statistics64`, `sysctl`) — no private frameworks, kernel extensions,
or shell-command scraping. It is built from the ground up for Mac App Store
submission and hardened notarization.

---

## Quick Start

**Build the DMG from source — no Xcode required:**

```bash
./scripts/build_from_source.sh
```

**Requirements:** macOS 13+ and [Xcode Command Line Tools](https://developer.apple.com/download/all/) (`xcode-select --install`).

**Output:** `build/sysmon-latest.dmg`

For a distribution-signed build:

```bash
SYS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build_from_source.sh
```

---

## Table of Contents

1. [Project Architecture](#a-project-architecture--setup)
2. [Core System Monitoring Engine](#b-core-system-monitoring-engine)
3. [SwiftUI User Interface](#c-swiftui-user-interface-implementation)
4. [Deployment & Distribution](#d-deployment--distribution-packaging)
5. [Directory Layout Reference](#directory-layout-reference)

---

## A. Project Architecture & Setup

### Build approach

sysmon is built with `swiftc` directly — no Xcode GUI or `xcodebuild` required.

```
./scripts/build_from_source.sh
```

The script compiles the main app and WidgetKit extension, assembles the
`.app` bundle (including `Contents/PlugIns/` for the widget), generates
entitlements, code-signs, and packages a DMG — all from a single command.

Requirements: macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

### Entitlements & App Groups

Both targets share data via **App Groups**. The App Group ID used throughout
the code is:

```
group.com.sysmon.shared
```

Entitlements are auto-generated into `build/` at build time. No manual
configuration needed. The `.entitlements` files in this repository contain
the required keys. If you change the App Group ID, update
`AppGroupStore.swift` accordingly.

### Sandbox Compatibility

`host_statistics`, `host_statistics64`, and `sysctl` operate **entirely
within the App Sandbox**. No temporary exceptions or special entitlements
are required. The only entitlements needed are:

| Entitlement                            | Purpose                       |
|----------------------------------------|-------------------------------|
| `com.apple.security.app-sandbox`       | Required for Mac App Store    |
| `com.apple.security.application-groups`| Share stats with widget       |

**No** network, file-access, camera, microphone, or Bluetooth entitlements
are used.

---

## B. Core System Monitoring Engine

### `SystemMonitorEngine` (`Shared/SystemMonitorEngine.swift`)

A thread-safe actor-lite class (`@unchecked Sendable`) that:

- Uses `host_statistics()` with `HOST_CPU_LOAD_INFO` to read accumulated CPU
  ticks (user, system, idle, nice) and computes per-state percentages.

- Uses `host_statistics64()` with `HOST_VM_INFO64` to read VM page counts
  (free, active, inactive, wired, compressed) and multiplies by the kernel
  page size to get byte values.

- Uses `sysctlbyname("hw.memsize")` to get total physical memory.

- Runs a low-overhead `DispatchSourceTimer` on a `.utility` QoS queue at a
  configurable interval (default 2 seconds). Each invocation is O(1).

- Exposes an `AsyncStream<SystemSnapshot>` so that SwiftUI views can consume
  updates with `for await` loops.

- Persists the latest snapshot into the App Group `UserDefaults` suite via
  `AppGroupStore`, so the Widget Extension's `TimelineProvider` always has
  fresh data.

### `SystemSnapshot` & Data Models (`Shared/SystemMonitorData.swift`)

Immutable value types conforming to `Sendable`:

| Type              | Fields                                                              |
|-------------------|---------------------------------------------------------------------|
| `CPUStats`        | `systemLoad`, `userLoad`, `systemCPULoad`, `niceLoad` (0–100 %)     |
| `MemoryStats`     | `totalBytes`, `usedBytes`, `wiredBytes`, `activeBytes`, `inactiveBytes`, `freeBytes`, `compressedBytes`, `usagePercentage`, `usedGB`, `totalGB` |
| `SystemSnapshot`  | `cpu: CPUStats`, `memory: MemoryStats`, `timestamp: Date`           |

---

## C. SwiftUI User Interface Implementation

### Menu Bar Component

**`sysmonApp.swift`** — The `@main` entry point. Creates a `MenuBarExtra`
scene with a custom `label` view and a `window`-style dropdown.

**`MenuBarLabelView.swift`** — The compact text row displayed in the menu
bar:

```
 [CPU icon] 42%  |  [RAM icon] 68%
```

**`StatsDetailView.swift`** — The dropdown panel (280–300 pt wide) showing:
- CPU section: progress bar, user/system/idle breakdown
- Memory section: progress bar, used/total GB
- Footer: last-updated timestamp, refresh button, **Quit** button (⌘Q)

**`MenuBarViewModel.swift`** — `ObservableObject` that owns the
`SystemMonitorEngine`, subscribes to its `AsyncStream`, publishes
`@Published` properties, and flushes each snapshot to `AppGroupStore`.

### WidgetKit Component

**`sysmonWidget.swift`** — The `Widget` definition. Uses a
`StaticConfiguration` with `SystemStatsProvider` as the timeline provider.
Supported families: `.systemSmall`, `.systemMedium`.

**`SystemStatsProvider`** — Implements `TimelineProvider`:
- `placeholder` — Static dummy data for the widget gallery.
- `getSnapshot` — Reads `AppGroupStore.latestSnapshot`.
- `getTimeline` — Reads latest snapshot, schedules next refresh in 60 s.

**`SystemStatsWidgetView.swift`** — SwiftUI rendering:
- **Small**: Two stacked `Gauge` views (CPU + RAM) with circular capacity style.
- **Medium**: Horizontal layout with two gauges, percentage text, and
  memory used/total GB text.

---

## D. Deployment & Distribution Packaging

### Option 1: Standalone CLI build (recommended, no Xcode needed)

```bash
./scripts/build_from_source.sh
```

The script will:
1. Detect the macOS SDK automatically via `xcrun`
2. Compile the main app and widget extension with `swiftc`
3. Assemble the `.app` bundle (Info.plists, PlugIns directory, etc.)
4. Generate entitlements on-the-fly
5. Code-sign both targets — ad-hoc by default, or with a Developer ID
   identity if `SYS_SIGN_IDENTITY` is set
6. Verify the code signature
7. Package everything into `build/sysmon-latest.dmg` via `hdiutil`

**For a distribution-signed build:**

```bash
SYS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build_from_source.sh
```

### Option 2: Homebrew Cask Deployment (notarized DMG + Tap)

For fully automated deployment to a custom Homebrew Tap, use the
`deploy_brew.sh` script. It compiles, signs, notarizes, packages a DMG,
notarizes the DMG, and generates the Ruby Cask file — all in one command.
**No Xcode or xcodebuild required** — it uses `swiftc` directly.

**1. Set your credentials:**

```bash
export SYS_APPLE_ID="you@example.com"
export SYS_APPLE_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # app-specific password
export SYS_TEAM_ID="ABCDEF1234"
export SYS_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDEF1234)"
```

**2. Run the deployment:**

```bash
./scripts/deploy_brew.sh
```

The script will:
1. Pre-flight: verify tools, credentials, keychain identity
2. Compile the main app and widget extension with `swiftc`
3. Assemble the `.app` bundle (Info.plist, icons, entitlements)
4. Sign with `--options runtime --timestamp` for hardened runtime
5. Notarize the `.app` via `xcrun notarytool --wait` and staple
6. Package into `build/sysmon.dmg` (UDZO compressed, zlib level 9)
7. Notarize the `.dmg` and staple the ticket
8. Compute SHA-256 and write the Ruby Cask to `dist/sysmon.rb`
9. Copy the versioned DMG to `dist/sysmon-<version>.dmg`

Output files:
| File | Location |
|------|----------|
| Notarized DMG | `dist/sysmon-<version>.dmg` |
| Homebrew Cask | `dist/sysmon.rb` |

**3. Set up the Homebrew Tap repository:**

Create a public GitHub repository named `homebrew-sysmon`:

```
https://github.com/YOUR_GITHUB_USER/homebrew-sysmon
```

Clone it, add the generated Cask, create a release with the DMG:

```bash
git clone git@github.com:YOUR_GITHUB_USER/homebrew-sysmon.git
cd homebrew-sysmon
mkdir -p Casks
cp /path/to/sysmon/dist/sysmon.rb Casks/sysmon.rb

# Attach the DMG as a GitHub Release asset
gh release create v1.0.0 /path/to/sysmon/dist/sysmon-1.0.0.dmg \
  --title "sysmon v1.0.0"

git add Casks/sysmon.rb
git commit -m "Add sysmon v1.0.0"
git push origin main
```

**4. Install via Homebrew:**

```bash
brew tap YOUR_GITHUB_USER/sysmon
brew install --cask sysmon
```

To uninstall cleanly (the Cask's `zap trash:` section removes all app data):

```bash
brew uninstall --cask --zap sysmon
```

The `zap trash:` directives clean:
- `~/Library/Application Scripts/group.com.sysmon.shared`
- `~/Library/Application Support/sysmon`
- `~/Library/Caches/com.sysmon.app`
- `~/Library/Containers/com.sysmon.app`
- `~/Library/Containers/com.sysmon.app.widget`
- `~/Library/Group Containers/group.com.sysmon.shared`
- `~/Library/Preferences/com.sysmon.app.plist`
- `~/Library/Saved Application State/com.sysmon.app.savedState`

### Notarize & Staple (manual)

```bash
xcrun notarytool submit build/sysmon-latest.dmg \
  --apple-id "your@email.com" \
  --team-id ABCD123456 \
  --wait

xcrun stapler staple build/sysmon-latest.dmg
```

### Create a GitHub Release

Once the DMG is built (and optionally notarized), publish it as a GitHub
Release with a single command:

```bash
./scripts/release.sh 1.0.0
```

This script will:
1. Create and push an annotated git tag (`v1.0.0`)
2. Generate release notes from `CHANGELOG.md` (or use sensible defaults)
3. Create the GitHub Release via `gh`
4. Attach `build/sysmon-latest.dmg` as a downloadable asset

**Requirements:** [GitHub CLI](https://cli.github.com/) (`brew install gh`)
and authentication (`gh auth login`).

The full release pipeline from source to GitHub is two commands:

```bash
./scripts/build_from_source.sh    # compile → DMG
./scripts/release.sh 1.0.0        # tag → release → upload
```

---

## Directory Layout Reference

```
sysmon/
├── .gitignore
├── CHANGELOG.md
├── README.md
├── Shared/
│   ├── SystemMonitorData.swift       # Data models
│   ├── SystemMonitorEngine.swift     # Core sampling engine
│   └── AppGroupStore.swift           # App Group persistence
├── sysmon/
│   ├── sysmonApp.swift               # @main entry point
│   ├── MenuBarViewModel.swift        # ObservableObject binding
│   ├── MenuBarLabelView.swift        # Menu bar text label
│   ├── StatsDetailView.swift         # Drop-down detail panel
│   ├── Info.plist
│   └── sysmon.entitlements
├── sysmonWidget/
│   ├── sysmonWidget.swift            # Widget definition + provider
│   ├── SystemStatsWidgetView.swift   # Widget SwiftUI views
│   ├── Info.plist
│   └── sysmonWidget.entitlements
└── scripts/
    ├── build_from_source.sh          # Standalone CLI build (no Xcode required)
    ├── deploy_brew.sh                # Full notarize + DMG + Homebrew Cask deployer
    ├── generate_cask.sh              # DMG → Cask generator (for Homebrew Tap)
    ├── release.sh                    # GitHub Release creator (main repo)
    └── release_tap.sh                # DMG uploader (Tap repo releases)
