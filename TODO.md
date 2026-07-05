# Homebrew Deployment — Task List

## Critical

- [x] **#1 Add `depends_on arch: :arm64` to Cask** — Added to both `Casks/mickyhq-sysmon.rb` and `scripts/generate_cask.sh` template.
- [x] **#2 Automate notarization in the build pipeline** — Added `notarize_dmg()` function to `scripts/build_from_source.sh`. Supports `SYS_NOTARY_KEYCHAIN_PROFILE` or `SYS_NOTARY_APPLE_ID`+`SYS_NOTARY_TEAM_ID` env vars.
- [ ] **#3 Ensure Cask SHA matches an uploaded DMG** — **Action required at release time:** After building a notarized DMG and uploading it to the Tap repo's GitHub Release, run `./scripts/generate_cask.sh` to regenerate the Cask with the correct SHA-256. The CI/CD workflow does this automatically when a version tag is pushed.

## Missing Cask Stanzas

- [x] **#4 Add `livecheck` block to Cask** — Added Atom feed-based livecheck to both Cask and generate_cask.sh template.
- [x] **#5 Add `auto_updates true` to Cask** — Added to both Cask and generate_cask.sh template.
- [x] **#6 Add `caveats` block to Cask** — Added informative caveats about menu bar behavior, privacy settings, and widget setup to both Cask and generate_cask.sh template.

## Build Pipeline

- [x] **#7 Single version source of truth** — Created `VERSION` file. Updated `build_from_source.sh`, `release.sh`, and `generate_cask.sh` to read from it.
- [x] **#8 Add GitHub Actions CI/CD workflow** — Created `.github/workflows/release.yml` that builds, notarizes, creates releases in both repos, and updates the Cask automatically on version tag push.

## Minor / Polish

- [x] **#9 Remove empty `Cask/` directory** — Deleted.
- [x] **#10 Add `uninstall` block to Cask** — Added `uninstall delete:` for App Group directories to both Cask and generate_cask.sh template.
- [ ] **#11 Consider naming conventions** — **Decision deferred.** Current naming (`mickyhq-sysmon` Cask, `mickyhq/sysmon` tap) works but is verbose. Consider renaming the Cask to `sysmon` and the tap repo to `homebrew-sysmon` (already the repo name) for a shorter `brew install --cask mickyhq/sysmon/sysmon` command. This would require:
  1. Renaming `Casks/mickyhq-sysmon.rb` → `Casks/sysmon.rb`
  2. Updating the `cask` declaration in the Cask file
  3. Updating `scripts/generate_cask.sh` output filename and placeholder refs
  4. Updating `README.md` install instructions
  5. Updating `scripts/deploy_brew.sh` references