# Changelog

## 2.1.0 - 2026-08-16

Review pass over the 2.0 rewrite. Several of these were found only by running
the code for real - the 2.0 dry runs structurally could not reach them.

### Fixed
- **Undo was completely broken.** `ConvertFrom-Json` in Windows PowerShell 5.1
  emits a JSON array as a *single* pipeline object, so
  `@(Get-Content ... | ConvertFrom-Json)` produced a one-element array holding
  the real array. That corrupted the snapshot file from the third recorded
  change onward and made every undo fail. Snapshot I/O now goes through
  `Read-SnapshotFile`, and undo is verified end-to-end (DWord, Binary, String,
  and newly-created values).
- **Every real run emitted malformed result rows.** `Write-OptimizerLog`
  returned its formatted line, which leaked into each tweak's output stream
  alongside the real result object; the UIs rendered those as blank `[FAIL]`
  rows. The WhatIf branches return before logging, which is exactly why dry
  runs looked clean. The logger no longer returns anything, and native
  `powercfg` / appx stdout is suppressed for the same reason.
- **Crash on machines missing a service.** `(Get-Service X -EA SilentlyContinue).StartType`
  throws under `Set-StrictMode -Version Latest`, so the menu died on
  already-debloated or LTSC images. Added `Get-ServiceStartTypeSafe`.
- **Scheduled-task undo silently no-opped.** `Get-ScheduledTask` only matches a
  `TaskPath` with a trailing backslash, which `Split-Path` strips. Both the
  disable and undo paths now share `Split-TaskPath`.
- Dry runs wrote nothing to the log, because `Add-Content` inherited `-WhatIf`.
- `DiskCleanup` and `Startup` both keyed their status off `HiberbootEnabled`,
  so a startup-only run made disk cleanup falsely report "Applied".
- Removed the duplicate `%TEMP%` / `%LOCALAPPDATA%\Temp` pass (same folder).
- Removed `DoNotConnectToWindowsUpdateInternetLocations`, which can block
  Surface firmware and driver updates and was not a performance tweak.

### Added
- **Hardware-aware tweaks** (`Get-DeviceProfile`). Tweaks that are standard
  desktop advice but harmful on a fanless 2-core/4GB/eMMC tablet are now
  skipped with a logged reason instead of applied blindly:
  forcing the High Performance power plan (thermal throttling on a fanless
  device), disabling CPU power throttling on battery, disabling Superfetch and
  SysMain on eMMC/low-RAM, and `DisablePagingExecutive` on 4GB. Both UIs show
  the detected profile and report skips as `[SKIP]`.
- Memory compression now detects that SysMain is disabled rather than silently
  doing nothing - the 1.x/2.0 "disable SysMain" and "enable memory
  compression" steps contradicted each other.
- New categories: **Disable Game Bar capture**, **Disable reserved storage**
  (~7GB back on a 64GB eMMC device), **Enable Storage Sense**.
- Status caching. A full status sweep costs ~360ms and both UIs redrew on every
  keystroke; on a 2-core Surface Go that was seconds of lag per toggle. Cached
  sweeps now cost ~1ms.

### Changed
- GUI is touch- and portrait-aware: finger panning on the checklist, whole-row
  tap targets with a scaled-up checkbox glyph, and a layout that collapses to a
  single column below 860 DIP so it fits a Surface Go in portrait.

## 2.0.0 - 2026-08-16

Full rewrite of the tooling around the same set of tweaks. Behavior of each
individual tweak is unchanged from 1.2; what changed is the engine and the
interface around it.

### Added
- `TouchOptimizer.psm1`: shared PowerShell engine. Every tweak is now a
  data-driven, logged, `-WhatIf`-aware function instead of a bare `reg add` /
  `sc config` line, so dry runs, per-item pass/fail, and consistent logging
  come for free.
- Snapshot-based undo for all non-destructive categories (registry values and
  service start types are recorded before being changed and can be replayed
  in reverse), independent of System Restore.
- `TouchOptimizer.ps1`: new console UI with a multi-select checklist, live
  per-category status (Applied / Partial / Not applied), and a confirmation
  step before any destructive action.
- `TouchOptimizerGUI.ps1`: new WPF GUI with the same checklist, live status,
  a background runspace so applying tweaks never freezes the window, and a
  progress bar + streaming log pane.
- `windows_11_touch_optimizer_gui.bat`: launcher for the GUI.
- `LICENSE` (MIT).

### Fixed
- **Double UAC prompt on launch.** The 1.2 batch file's elevation relaunch
  fell through to a second admin check in the original (non-elevated)
  window, which popped a confusing "must be run as administrator" message
  right after telling the user a new elevated window had opened. Elevation
  is now a single, atomic relaunch-and-exit (`Assert-Elevation` in the
  module), used by both entry points.
- **Silent tweak failures.** Most of the 1.2 batch functions piped `reg`/`sc`
  output to `nul`, so a failing tweak looked identical to a succeeding one
  and wasn't in the log despite the README's "logging for easy auditing"
  claim. Every tweak now reports and logs `[OK]`/`[FAIL]` individually.

### Changed
- `windows_11_touch_optimizer.bat` is now a thin bootstrap that launches
  `TouchOptimizer.ps1`; all menu and tweak logic moved to PowerShell.

## 1.2 and earlier
See git history / prior README revisions.
