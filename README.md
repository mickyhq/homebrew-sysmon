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

**macOS Gatekeeper warning:** If macOS blocks the app with *"Apple could not verify sysmon is free of malware"*, see [Gatekeeper Workaround](#gatekeeper-workaround) below.

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

### Option 2: Install via Homebrew (recommended for users)

sysmon is distributed as a **Homebrew Cask** through a custom Tap.
Run these three commands to find and install it:

```bash
brew tap mickyhq/sysmon
brew trust mickyhq/sysmon
brew search sysmon
```

**What these commands do:**

| Command | Purpose |
|---------|---------|
| `brew tap mickyhq/sysmon` | Adds the sysmon Tap repository (`github.com/mickyhq/homebrew-sysmon`) to your local Homebrew installation so Homebrew can discover the Cask. |
| `brew trust mickyhq/sysmon` | Marks the Tap as trusted. When a tap is trusted, Homebrew will install its formulae/casks without prompting for confirmation each time. This is safe for taps you control or trust. |
| `brew search sysmon` | Searches all tapped repositories (including `mickyhq/sysmon`) for packages matching "sysmon". You should see `mickyhq/sysmon/mickyhq-sysmon` in the results. |

**Install:**

```bash
brew install --cask mickyhq/sysmon/mickyhq-sysmon
```

**Uninstall** (the Cask's `zap trash:` section removes all app data):

```bash
brew uninstall --cask --zap mickyhq-sysmon
```

The `zap trash:` directives clean:
- `~/Library/Application Scripts/group.com.sysmon.shared`
- `~/Library/Application Support/sysmon`
- `~/Library/Caches/com.sysmon.app`
- `~/Library/Containers/com.sysmon.app`
- `~/Library/Containers/com.sysmon.app.widget`
- `~/Library/Group Containers/group.com.sysmon.shared`
- `~/Library/HTTPStorages/com.sysmon.app`
- `~/Library/Preferences/com.sysmon.app.plist`
- `~/Library/Saved Application State/com.sysmon.app.savedState`
- `~/Library/WebKit/com.sysmon.app`

### Option 3: Homebrew Cask Deployment (for maintainers — building and publishing the Tap)

The Cask lives at `Casks/mickyhq-sysmon.rb`. Homebrew only discovers Casks
from this top-level `Casks/` directory.

**1. Build a distribution DMG:**

```bash
export SYS_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDEF1234)"
./scripts/build_from_source.sh
```

Notarize and staple `build/sysmon-latest.dmg` before publishing it.
The build script can handle notarization automatically if you set
`SYS_NOTARY_KEYCHAIN_PROFILE` or `SYS_NOTARY_APPLE_ID` + `SYS_NOTARY_TEAM_ID`.

**2. Create the release and update the Cask:**

```bash
./scripts/release_tap.sh 1.0 build/sysmon-latest.dmg
./scripts/generate_cask.sh build/sysmon-latest.dmg 1.0
```

Commit and push the updated Cask:

```bash
git add Casks/mickyhq-sysmon.rb
git commit -m "Update mickyhq-sysmon to v1.0"
git push origin main
```

**3. Verify the published Tap:**

```bash
./scripts/deploy_brew.sh
```

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
    ├── deploy_brew.sh                # Published Homebrew Cask verifier
    ├── generate_cask.sh              # DMG → Cask generator (for Homebrew Tap)
    ├── release.sh                    # GitHub Release creator (main repo)
    └── release_tap.sh                # DMG uploader (Tap repo releases)

---

## Gatekeeper Workaround

If you built sysmon locally without a paid Apple Developer account (ad-hoc
signature), macOS Gatekeeper will block the app with:

> *"sysmon" cannot be opened because Apple cannot verify it is free of malware.*

This is expected — only Developer ID-signed + notarized apps pass Gatekeeper
automatically. Use one of these methods to bypass it:

### Method 1: System Settings (recommended)

1. Open **System Settings → Privacy & Security**
2. Scroll to the **Security** section at the bottom
3. You will see: `"sysmon" was blocked to protect your Mac`
4. Click **Open Anyway**
5. Confirm by clicking **Open Anyway** in the popup

### Method 2: Right-click open

1. In Finder, navigate to `build/sysmon.app`
2. **Right-click** (or Control-click) the app icon
3. Select **Open** from the context menu
4. Click **Open** in the dialog that appears

This adds a one-time exception and you won't be prompted again.

### Method 3: Remove quarantine attribute (terminal)

```bash
xattr -cr build/sysmon.app
```

This strips the `com.apple.quarantine` extended attribute that macOS attaches
to downloaded files.

### First-launch sandbox notification

When you first launch sysmon (or after clearing its sandbox container), macOS
may show:

> *"Keeping app data separate makes it easier to manage your privacy and security."*

This is **normal and expected** — it's macOS creating the sandbox container for
the app. It only appears once per user account. Click **OK** to dismiss it.
This happens because sysmon uses the App Sandbox entitlement, which is
required for Mac App Store submission and provides defense-in-depth security.

### Repeating "would like access data from other apps" prompt

If the permission dialog keeps reappearing even after clicking **Allow**, the
app's sandbox container may be in a bad state. This typically happens when
running the app from outside `/Applications` (e.g., from the `build/`
directory). To fix it:

**Step 1 — Copy (not move) the app to `/Applications`:**

```bash
cp -R build/sysmon.app /Applications/sysmon.app
xattr -cr /Applications/sysmon.app
```

**Step 2 — Reset sandbox containers via Finder (not Terminal):**

The `~/Library/Containers` folder is protected by System Integrity Protection
and requires Full Disk Access — using Finder is more reliable:

1. Open **Finder** and press **⌘⇧G** (Go to Folder)
2. Paste each of these paths one at a time and delete the folder:
   - `~/Library/Containers/com.sysmon.app`
   - `~/Library/Containers/com.sysmon.app.widget`
   - `~/Library/Group Containers/group.com.sysmon.shared`

   If a folder doesn't exist, skip it and move to the next.

**Step 3 — Reset TCC permissions from Terminal:**

This command works without extra permissions:

```bash
tccutil reset All com.sysmon.app
```

Then launch `/Applications/sysmon.app` — the prompt should appear only once
and stay accepted after clicking **Allow**.

> **If "Operation not permitted" occurs on `rm -rf`:** Terminal needs **Full Disk Access**
> to delete sandbox containers. Grant it in **System Settings → Privacy & Security →
> Full Disk Access** → add Terminal. Alternatively, use Finder as described in Step 2.

### Why does Gatekeeper blocking happen?

- **Ad-hoc signed builds** (the default when no `SYS_SIGN_IDENTITY` is set) are
  not trusted by Gatekeeper.
- **Developer ID signed + notarized builds** pass Gatekeeper without any
  workaround. To produce one, you need a paid Apple Developer Program membership
  ($99/year) and run:

  ```bash
  SYS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
    SYS_NOTARY_KEYCHAIN_PROFILE=sysmon-notary \
    ./scripts/build_from_source.sh
  ```

  See [Notarize & Staple](#notarize--staple-manual) for details on setting up
  notarization credentials.
