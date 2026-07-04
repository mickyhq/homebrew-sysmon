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

This project supports **two** build paths:

| Path | Command | Requires Xcode GUI? |
|------|---------|---------------------|
| **Standalone CLI** (recommended) | `./scripts/build_from_source.sh` | No — only Command Line Tools |
| Xcode project (IDE) | Open `.xcodeproj` → Archive | Yes |

The standalone script uses `swiftc` directly to compile, assemble, sign,
and package a complete `.app` bundle with its `.appex` widget extension
embedded inside `Contents/PlugIns/`.

### Xcode Project Structure (if using the IDE)

```
sysmon.xcodeproj
├── sysmon (Main App Target)
│   ├── sysmonApp.swift
│   ├── MenuBarViewModel.swift
│   ├── MenuBarLabelView.swift
│   ├── StatsDetailView.swift
│   ├── Info.plist
│   └── sysmon.entitlements
│
├── sysmonWidget (Widget Extension Target)
│   ├── sysmonWidget.swift
│   ├── SystemStatsWidgetView.swift
│   ├── Info.plist
│   └── sysmonWidget.entitlements
│
└── Shared (Folder reference, added to both targets)
    ├── SystemMonitorData.swift
    ├── SystemMonitorEngine.swift
    └── AppGroupStore.swift
```

### Step-by-step Xcode Configuration

1. **Create a new macOS project** → App template, SwiftUI interface,
   Language: Swift 5, Minimum Deployment: **macOS 13.0**.

2. **Add Widget Extension target**:
   - `File → New → Target → macOS → Widget Extension`
   - Name it `sysmonWidget`
   - Deselect "Include Configuration App Intent" (not needed here)
   - Delete the auto-generated `sysmonWidget.swift` and replace with ours

3. **Add Shared folder**:
   - Right-click the project root in the Navigator → `Add Files to "sysmon"…`
   - Select the `Shared/` folder
   - In the destination sheet, check **both** targets:
     - ✅ sysmon
     - ✅ sysmonWidget

4. **Delete auto-generated `ContentView.swift`** from the main target (we
   do not show a window).

5. **Set `LSUIElement = YES`** in the main target's Info.plist so the app
   does not appear in the Dock. (Already set in our `Info.plist`.)

### Entitlements & App Groups

Both targets share data via **App Groups**. The App Group ID used throughout
the code is:

```
group.com.sysmon.shared
```

**Using the standalone build script:** Entitlements are auto-generated into
`build/` at build time. No manual configuration needed.

**Using Xcode:**
1. Main target → `Signing & Capabilities` → `+` → **App Groups**
   - Add `group.com.sysmon.shared`
2. Widget Extension target → `Signing & Capabilities` → `+` → **App Groups**
   - Add `group.com.sysmon.shared`

The `.entitlements` files in this repository already contain these entries.
If you change the App Group ID, update `AppGroupStore.swift` accordingly.

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

### Option 2: Xcode archive (alternative)

```
Product → Scheme → Edit Scheme → Archive → Release
Product → Archive
```

Or via command line:

```bash
xcodebuild archive \
  -project sysmon.xcodeproj \
  -scheme sysmon \
  -configuration Release \
  -archivePath build/sysmon.xcarchive
```

Then run the archive-based packaging script:

```bash
./scripts/build_dmg.sh build/sysmon.xcarchive
```

### Notarize & Staple (both paths)

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

### Critical Xcode Settings for Mac App Store

Configure these **before** your first archive to avoid painful refactoring:

| Setting                          | Main Target (sysmon)                | Widget Extension (sysmonWidget)      |
|----------------------------------|-------------------------------------|--------------------------------------|
| **Bundle Identifier**            | `com.yourcompany.sysmon`            | `com.yourcompany.sysmon.widget`      |
| **Team**                         | Your Apple Developer Team           | Same team (inherits, auto-selected)  |
| **Signing Certificate**          | "Apple Development" (debug) / "Apple Distribution" (release) | Same |
| **Deployment Target**            | macOS 13.0                          | macOS 13.0                           |
| **App Category** (App Store)     | Utilities                           | (inherits from parent)               |
| **App Sandbox**                  | YES                                 | YES                                  |
| **App Groups**                   | `group.com.sysmon.shared`           | `group.com.sysmon.shared`            |
| **Hardened Runtime**             | YES (required for notarization)     | YES (required)                       |

**Important**: The Widget Extension's Bundle ID **must** start with the main
app's Bundle ID. For example, if the main app is `com.foo.sysmon`, the
widget must be `com.foo.sysmon.widget`.

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
    ├── build_dmg.sh                  # Archive → DMG packaging (Xcode users)
    └── release.sh                    # GitHub Release creator