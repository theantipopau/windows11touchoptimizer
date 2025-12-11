# Windows 11 Touchscreen Device Optimiser

A menu-driven Windows batch utility that prunes bloatware, tones down telemetry, and applies performance tweaks tailored for low-power touchscreen devices (Surface Go, Surface Go 2, tablets, 2-in-1s, etc.). The script keeps key pen and touch services intact while maximising responsiveness and reclaiming resources.

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
- **Logging** to `logs\surface_go_optimizer_*.log` beside the script for easy auditing.

## Prerequisites
1. Windows 11 build with System Protection enabled if you want automatic restore points.
2. An administrator account. The script checks for elevation and will exit if it is not run as admin.
3. Optionally export a full system image before aggressive cleanup.

## Quick start
1. Copy the repository folder somewhere local (e.g., `C:\Windows Debloat`).
2. Double-click `windows_11_touch_optimizer.bat` (or right-click and choose **Run as administrator**). A double-click shows a "Requesting administrator approval" message, triggers UAC, and pauses until you confirm; once approved, a fresh elevated `cmd` window launches in the script folder and stays open on the optimizer menu.
3. From the menu, select `[1]` (or press `F`) to run **FULL OPTIMIZATION** for Surface Go 2, or `[2]` (press `R`) for the conservative recommended flow, or pick individual steps.
4. Reboot after the script finishes so policy changes fully apply.

### Command-line shortcuts
- `/full` or `/recommended` run those flows without showing the menu.
- `/dry-run` prints the actions (and logs them) without making changes.
- `/no-restore` skips creating a restore point; `/skip-wu-cache` skips purging Windows Update downloads.
- `/revert:<telemetry|background|animations|startup|widgets|all>` re-enables a specific area without opening the menu.

You can also launch it from an elevated terminal:

```bat
cd /d C:\Windows Optimiser
start "" /wait powershell -Verb runAs .\windows_11_touch_optimizer.bat
```

## Menu reference
- `[1 / F]` **FULL OPTIMIZATION**: Runs ALL optimizations below in sequence (3-C) for maximum performance on Surface Go / touchscreen devices. Takes 5-10 minutes. **Recommended for Surface Go 2.**
- `[2 / R]` Recommended flow (conservative): create a restore point, remove consumer apps, disable telemetry, and apply core performance tweaks.
- `[3]` Create a restore point via PowerShell `Checkpoint-Computer`.
- `[4]` Remove inbox consumer apps (News, Weather, Xbox suite, Clipchamp, Spotify, TikTok, Microsoft Teams consumer, etc.) for all users and provisioned images.
- `[5]` Disable telemetry services (`DiagTrack`, `dmwappushservice`, CEIP tasks) and enforce app background restrictions.
- `[6]` Apply performance tweaks: sets `SCHEME_MIN`, disables transparency, caps network throttling, and ensures touch services remain on-demand.
- `[7]` Remove a small list of OEM promo packages if they ship on your device image.
- `[8]` Trim background services: disables SysMain, sets Windows Search indexing to manual, and turns off Start/lock-screen suggestions (Start search still works but may take longer the first time after reboot).
- `[9]` Free disk space: disables hibernation, purges temp folders and Windows Update caches, and runs component cleanup—expect Windows Update to re-download patches afterward.
- `[A]` Disable Widgets + Teams Chat (also hides the Copilot button) for a distraction-free taskbar.
- `[B]` Disable animations + visual effects: turns off taskbar animations, window animations, Aero Peek, and other visual effects for maximum touch responsiveness on low-spec hardware.
- `[C]` Optimise startup programs: disables fast startup (for cleaner boots), removes startup delays, and disables non-essential startup tasks.
- `[V]` Revert changes: choose to restore telemetry, background/search services, animations/touch typing defaults, startup tasks/features, widgets/chat, or all at once.
- `[X]` **RESTORE**: Launches Windows System Restore to undo changes if something breaks. Look for restore points named "SurfaceGoTouchOptimizer".

## Customizing the app list
Edit the `:RemoveConsumerApps` label inside `windows_11_touch_optimizer.bat` to add or remove package names. Use the exact `Get-AppxPackage` `Name` (for example `Microsoft.Todos`), one per line. The helper already removes both the installed app and the provisioned image so Store updates do not reinstall it.

## Rollback and safeguards
- A restore point is attempted at the beginning of the recommended flow. If System Protection is disabled, enable it and rerun option `[1]` to capture a snapshot.
- Every command logs to `logs\surface_go_optimizer_YYYYMMDD_hhmmss.log`. Review it to undo discrete registry edits manually if necessary.
- Touch-critical services (`TabletInputService`, `TextInputManagementService`) are explicitly kept in a manual start state so handwriting and the touch keyboard continue to work.

## Testing notes
Because the script changes system-level settings, it should only be run on hardware where you can verify the effects (ideally after creating a restore point or full backup). Dry-running it without admin rights will not exercise the logic, so there is no automated test harness included.

