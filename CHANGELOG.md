# Changelog

All notable changes to sysmon are documented in this file.

---

## [1.0.0] — 2026-07-04

### Added
- Initial release
- Real-time CPU and Memory stats in the macOS menu bar via `MenuBarExtra`
- Notification Center widget (Small + Medium families) via WidgetKit
- `SystemMonitorEngine` using `host_statistics` / `host_statistics64` / `sysctl`
- Standalone CLI build script — no Xcode required
- DMG packaging via `hdiutil`
- GitHub Release script (`scripts/release.sh`)
- App Sandbox compatible with App Group data sharing
- macOS 13.0+ deployment target

---

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).