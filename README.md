# Windows 11 Touchscreen Device Optimiser

A menu-driven Windows utility that prunes bloatware, tones down telemetry, and
applies performance tweaks tailored for low-power touchscreen devices
(Surface Go, Surface Go 2, tablets, 2-in-1s, etc.). It keeps key pen and touch
services intact while maximising responsiveness and reclaiming resources.

Two front-ends share one engine (`TouchOptimizer.psm1`):

- **Console** (`windows_11_touch_optimizer.bat` → `TouchOptimizer.ps1`) — a
  keyboard-driven checklist menu.
- **GUI** (`windows_11_touch_optimizer_gui.bat` → `TouchOptimizerGUI.ps1`) —
  a touch-friendly WPF window with the same tweaks as large toggles, live
  status, and a progress/log pane.

## What it does
- **Restore point helper** so you can roll back quickly if a change does not agree with your setup.
- **Consumer app cleanup** that removes common inbox/UWP apps and OEM promos for every user and provisioned images so they stay gone.
- **Telemetry and scheduled task throttling** by disabling DiagTrack, CEIP tasks, and background data sharing policies.
- **Performance + touch tweaks** that favor responsiveness (high performance plan, transparency off, throttling disabled) without disabling handwriting or touch keyboard services.
- **Background service trimming** (optional) that disables SysMain, Search indexing, and Start content suggestions to free CPU/RAM on tiny devices.
- **Disk cleanup helpers** that turn off hibernation, clear temp folders, remove stale Windows Update downloads, and run `DISM /StartComponentCleanup` to reclaim storage.
- **Taskbar decluttering** (optional) that hides Widgets, Teams Chat, and Copilot taskbar hooks if you want a distraction-free shell for Office/web work.
- **Animation disabling** (optional) that removes all window/taskbar animations, Aero effects, and visual fluff for instant UI response on low-spec touchscreens.
- **Startup optimization** (optional) that disables Fast Startup (hybrid boot), removes startup delays, and trims non-essential boot tasks for faster, cleaner startups.
- **Storage recovery for small eMMC devices**: disables Windows' ~7GB reserved storage and turns on Storage Sense so a 64GB Surface Go stays usable months later.
- **Game Bar capture disabling**, which costs CPU on every device even if you never open an Xbox app.
- **Per-tweak status, dry runs, and undo.** Each category shows Applied / Partial / Not applied, supports a `-WhatIf` dry run before you commit, and (except app/OEM removal and disk cleanup, which aren't reversible this way) can be undone individually without a full System Restore.
- **Hardware-aware safety** — see below.
- **Logging** to `logs\touch_optimizer_*.log` beside the script for auditing — every tweak now logs its own pass/fail, not just the top-level steps.

## Hardware-aware tweaks

A lot of standard Windows "debloat" advice is written for a desktop with 16GB
of RAM, an NVMe SSD and a fan. Applied unchanged to a fanless 2-core Surface Go
with 4GB and eMMC, several of those tweaks make the device *slower*. The tool
detects the hardware at startup (`Get-DeviceProfile`) and skips those with a
logged reason rather than applying them blindly:

| Tweak | Skipped when | Why |
|---|---|---|
| Force High Performance power plan | Fanless / battery device | Pins the CPU out of low power states; a fanless tablet thermally throttles and sustained performance drops while battery life collapses. Balanced is genuinely faster. |
| Disable CPU power throttling | Any battery device | Power Throttling de-prioritises *background* work. Disabling it on 2 cores lets background apps fight the foreground app for both of them. |
| Disable Superfetch | eMMC/HDD or <=4GB RAM | Prefetching exists to mask slow storage — it helps here rather than hurting. |
| Disable SysMain | eMMC/HDD or <=4GB RAM | Same reason, and SysMain also provides memory compression, which matters most on 4GB. |
| `DisablePagingExecutive` | <=4GB RAM | Pinning the kernel in RAM is a 16GB-desktop tweak; on 4GB it takes memory the foreground app needs. |

Both UIs show the detected profile ("Detected: 4GB RAM | 2 cores | eMMC |
battery") and report anything skipped as `[SKIP]` with the reason. On a desktop
none of these gates trigger and the tweaks apply as before.

## Prerequisites
1. Windows 11 build with System Protection enabled if you want automatic restore points.
2. An administrator account. Both launchers request elevation via UAC automatically.
3. Optionally export a full system image before aggressive cleanup.
4. Windows PowerShell 5.1 (ships with Windows 11) — no extra install needed.

## Quick start

### Console
1. Copy the repository folder somewhere local (e.g., `C:\Windows Debloat`).
2. Double-click `windows_11_touch_optimizer.bat` (or right-click and choose **Run as administrator**). UAC prompts once; the elevated console then opens directly on the checklist menu.
3. Toggle tweaks by number, then press `G` to run your selection, or use `F` (full) / `R` (recommended preset) as one-key shortcuts.
4. Reboot after the script finishes so policy changes fully apply.

### GUI
1. Double-click `windows_11_touch_optimizer_gui.bat` (or run as administrator).
2. Check the tweaks you want (each shows its current status), or click **Recommended preset**.
3. Click **Dry run (WhatIf)** to preview what would change, or **Apply selected** to run it — the log pane and progress bar update live without freezing the window.
4. Use **Undo selected category** to revert an individually-tracked category, or **Open System Restore** to roll back everything at once.

You can also launch either one from an elevated terminal:

```bat
cd /d "C:\Windows Optimiser"
powershell -NoProfile -ExecutionPolicy Bypass -File .\TouchOptimizer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\TouchOptimizerGUI.ps1
```

## Tweak categories
Both UIs are built from the same list (`Get-OptimizerCategories` in
`TouchOptimizer.psm1`):

| Category | What it does | Reversible |
|---|---|---|
| Create restore point | `Checkpoint-Computer` snapshot named "TouchOptimizer" | Restore point itself is the rollback |
| Remove consumer apps | Uninstalls inbox UWP apps (News, Xbox suite, Spotify, TikTok, etc.) for all users + provisioned images | Not reversible — reinstall via Store |
| Disable telemetry | Disables DiagTrack/CEIP services + scheduled tasks, sets telemetry policy to minimum | Undo available |
| Performance + touch tweaks | High performance power plan, disables transparency/throttling, keeps touch/pen services intact | Undo available |
| Remove OEM promo apps | Removes common OEM-bundled promo packages if present | Not reversible — reinstall via Store |
| Trim background services | Disables SysMain/MapsBroker/TrkWks, sets Search indexing to manual, disables Start suggestions | Undo available |
| Free disk space | Disables hibernation, clears temp + Windows Update cache, runs DISM component cleanup | Partially reversible (hibernation only) |
| Disable Widgets + Teams Chat | Hides Widgets, Teams Chat, and the Copilot taskbar button | Undo available |
| Disable animations + visual effects | Turns off window/taskbar animations, Aero Peek, touch-keyboard autocorrect/prediction | Undo available |
| Optimize startup | Disables Fast Startup, trims non-essential scheduled tasks + Xbox services, enables memory compression | Undo available |
| Disable Game Bar capture | Turns off Xbox Game Bar background recording | Undo available |
| Disable reserved storage | Reclaims the ~7GB Windows reserves for updates | Re-enable via `Set-WindowsReservedStorageState` |
| Enable Storage Sense | Automatic temp/recycle-bin cleanup every 30 days | Undo available |

"Undo available" means the exact prior registry value / service start type is
replayed back — it's tracked per run in `logs\snapshots\<Category>.json` and
cleared once undone. It is independent of System Restore, which remains the
catch-all for everything (including the non-reversible categories).

## Customizing the app list
Edit `$Script:ConsumerAppList` / `$Script:OemPromoList` near the top of
`TouchOptimizer.psm1` to add or remove package names. Use the exact
`Get-AppxPackage` `Name` (for example `Microsoft.Todos`), one per line. The
helper removes both the installed app and the provisioned image so Store
updates do not reinstall it.

## Rollback and safeguards
- Create a restore point before making changes — both UIs offer it as a one-click action, and the `F`/Full and `R`/Recommended presets create one automatically.
- Every tweak logs its own outcome to `logs\touch_optimizer_YYYYMMDD_hhmmss.log`, including failures (fixed in 2.0 — the 1.x batch script silently discarded most command output).
- Non-destructive categories can be undone individually via the console's `U` command or the GUI's **Undo selected category** — see the table above for which ones qualify.
- Touch-critical services (`TabletInputService`, `TextInputManagementService`) are explicitly kept in a manual start state so handwriting and the touch keyboard continue to work.
- Use **Dry run (WhatIf)** / the console's `W` command to preview exactly what a selection would change before committing.

## Testing notes
Because the script changes system-level settings, it should only be run on
hardware where you can verify the effects (ideally after creating a restore
point or full backup). `TouchOptimizer.psm1`'s functions all support
`-WhatIf`, so you can dry-run any category from a PowerShell prompt too:

```powershell
Import-Module .\TouchOptimizer.psm1
Invoke-OptimizerCategory -Id Telemetry -WhatIf
```

There is still no automated test harness — most of what this script does
(registry policy, service state, appx removal) only makes sense to verify
against a real Windows install. The undo path *is* verified end-to-end against
a scratch registry key (DWord, Binary, String, and newly-created values) since
it is the main safety claim.

Note on runtime: **"Free disk space" and "Optimize startup" are slow on eMMC.**
`DISM /StartComponentCleanup` and `Disable-WindowsOptionalFeature` can each
take many minutes on a Surface Go — budget 30-60 minutes for a full run on that
class of device, not the 5-10 minutes the 1.x script claimed. Everything else
finishes in seconds.

## License
[MIT](LICENSE)
