#requires -Version 5.1
<#
    TouchOptimizer.psm1
    Shared engine for the Windows 11 Touchscreen Device Optimiser.
    Used by both TouchOptimizer.ps1 (console) and TouchOptimizerGUI.ps1 (WPF GUI).
#>

Set-StrictMode -Version Latest

$Script:LogFile = $null
$Script:SnapshotDir = $null

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Initialize-OptimizerLog {
    param([Parameter(Mandatory)][string]$ScriptRoot)

    $logDir = Join-Path $ScriptRoot 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $Script:SnapshotDir = Join-Path $logDir 'snapshots'
    if (-not (Test-Path $Script:SnapshotDir)) { New-Item -ItemType Directory -Path $Script:SnapshotDir -Force | Out-Null }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Script:LogFile = Join-Path $logDir "touch_optimizer_$stamp.log"
    "=== Touch Optimizer started $(Get-Date) ===" | Out-File -FilePath $Script:LogFile -Encoding utf8
    return $Script:LogFile
}

function Get-OptimizerLogPath { return $Script:LogFile }

function Set-OptimizerLogPath {
    <#
        Points this module instance at an already-created log/snapshot
        location. Used by background runspaces (e.g. the GUI's apply job)
        so they write into the same session log instead of creating a new
        timestamped file via Initialize-OptimizerLog.
    #>
    param([Parameter(Mandatory)][string]$LogFile)
    $Script:LogFile = $LogFile
    $Script:SnapshotDir = Join-Path (Split-Path -Parent $LogFile) 'snapshots'
    if (-not (Test-Path $Script:SnapshotDir)) { New-Item -ItemType Directory -Path $Script:SnapshotDir -Force | Out-Null }
}

function Write-OptimizerLog {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warn', 'Error')][string]$Level = 'Info'
    )
    # Deliberately returns nothing. This used to return $line, which meant every
    # unassigned call inside a tweak leaked a bare string into that function's
    # output stream alongside the real result object - the UIs then rendered
    # those strings as blank [FAIL] rows. Dry runs never hit it because the
    # WhatIf branches return before logging, so it only showed up for real runs.
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Message
    if ($Script:LogFile) {
        # The GUI writes from a background runspace while the UI thread may also
        # log, so the file can genuinely be held open by the other writer.
        # Retry briefly rather than letting an IOException abort a tweak run.
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                # -WhatIf:$false so dry runs still record what they previewed;
                # without it Add-Content inherits WhatIf and the audit log for a
                # dry run comes out empty.
                Add-Content -Path $Script:LogFile -Value $line -Encoding utf8 -ErrorAction Stop -WhatIf:$false
                break
            }
            catch {
                Start-Sleep -Milliseconds 40
            }
        }
    }
}

function Get-ServiceStartTypeSafe {
    <#
        Set-StrictMode -Version Latest makes property access on a $null result
        throw, so '(Get-Service X -EA SilentlyContinue).StartType' crashes on
        any machine where the service does not exist (already-debloated
        images, LTSC, Server). Always go through this helper.
    #>
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    return $svc.StartType.ToString()
}

function Split-TaskPath {
    <#
        Get-ScheduledTask / Enable-ScheduledTask only match when TaskPath has a
        trailing backslash; Split-Path strips it. Both the disable and the undo
        path must use this helper or undo silently no-ops.
    #>
    param([Parameter(Mandatory)][string]$TaskPath)
    $folder = (Split-Path $TaskPath -Parent) -replace '/', '\'
    if (-not $folder.EndsWith('\')) { $folder += '\' }
    return [pscustomobject]@{ Folder = $folder; Name = (Split-Path $TaskPath -Leaf) }
}

# ---------------------------------------------------------------------------
# Elevation
# ---------------------------------------------------------------------------

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Elevation {
    <#
        Relaunches the calling script elevated exactly once, then exits the
        current (non-elevated) process. Callers should invoke this as the
        very first statement so there is never a fall-through path that can
        prompt twice, unlike the legacy batch relaunch logic.
    #>
    param([Parameter(Mandatory)][string]$ScriptPath)

    if (Test-IsAdmin) { return }

    Write-Host "[*] Requesting administrator approval via UAC..." -ForegroundColor Yellow
    try {
        $psExe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $psExe `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"") `
            -Verb RunAs -WorkingDirectory (Split-Path -Parent $ScriptPath) -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "[!] Elevation was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Right-click the script and choose 'Run as administrator'." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "[*] A new elevated window will open. You can close this window." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    exit 0
}

# ---------------------------------------------------------------------------
# Device profile
#
# Several tweaks that are standard advice on a desktop are actively harmful on
# a fanless 2-core tablet with 4 GB of RAM and eMMC storage (the Surface Go
# class this tool targets). Detect the hardware once and let each tweak opt out
# with a logged reason instead of applying blindly.
# ---------------------------------------------------------------------------

$Script:DeviceProfile = $null

function Get-DeviceProfile {
    param([switch]$Refresh)
    if ($Script:DeviceProfile -and -not $Refresh) { return $Script:DeviceProfile }

    $ramGB = 0
    $cores = 0
    $hasBattery = $false
    $systemDiskMedia = 'Unknown'

    try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) } catch {}
    try { $cores = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property NumberOfCores -Sum).Sum } catch {}
    if (-not $cores) { $cores = [Environment]::ProcessorCount }
    try { $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) } catch {}
    try {
        $sysLetter = ($env:SystemDrive).TrimEnd(':')
        $part = Get-Partition -DriveLetter $sysLetter -ErrorAction Stop
        $disk = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $part.DiskNumber }
        if ($disk) {
            $systemDiskMedia = $disk.MediaType
            # eMMC reports BusType 'SD' or 'MMC' and is much slower than SSD;
            # SysMain/prefetch genuinely help there, unlike on NVMe.
            if ($disk.BusType -in 'SD', 'MMC', 'USB') { $systemDiskMedia = 'eMMC' }
        }
    }
    catch {}

    $Script:DeviceProfile = [pscustomobject]@{
        RamGB           = $ramGB
        Cores           = $cores
        HasBattery      = $hasBattery
        SystemDiskMedia = $systemDiskMedia
        IsLowMemory     = ($ramGB -gt 0 -and $ramGB -le 4.5)
        IsLowCore       = ($cores -gt 0 -and $cores -le 2)
        IsSlowStorage   = ($systemDiskMedia -in 'eMMC', 'HDD', 'Unspecified')
        # Fanless tablets thermally throttle under a forced High Performance
        # plan, which makes sustained performance worse, not better.
        IsFanlessTablet = ($hasBattery -and $cores -le 4)
    }
    return $Script:DeviceProfile
}

function Write-SkippedTweak {
    param([Parameter(Mandatory)][string]$What, [Parameter(Mandatory)][string]$Reason)
    Write-OptimizerLog "SKIP $What - $Reason" -Level Warn
    return [pscustomobject]@{ Name = "$What - SKIPPED ($Reason)"; Success = $true; Skipped = $true }
}

# ---------------------------------------------------------------------------
# Snapshot store (per-category undo)
# ---------------------------------------------------------------------------

function Add-SnapshotEntry {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][pscustomobject]$Entry
    )
    if (-not $Script:SnapshotDir) { return }
    $file = Join-Path $Script:SnapshotDir "$Category.json"
    $existing = New-Object System.Collections.Generic.List[object]
    if (Test-Path $file) {
        foreach ($item in (Read-SnapshotFile -Path $file)) { $existing.Add($item) }
    }
    $existing.Add($Entry)
    # -InputObject (not the pipeline) so a single entry still serialises as a
    # JSON array rather than a bare object.
    ConvertTo-Json -InputObject $existing.ToArray() -Depth 5 | Out-File -FilePath $file -Encoding utf8
}

function Read-SnapshotFile {
    <#
        Windows PowerShell 5.1's ConvertFrom-Json emits a JSON array as a
        SINGLE pipeline object, so the natural-looking
        '@(Get-Content ... | ConvertFrom-Json)' yields a one-element array
        whose only member is the real array. That silently corrupted the
        snapshot on every third write and made undo fail outright. Assign
        first, then flatten.
    #>
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = Get-Content $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = ConvertFrom-Json $raw
        if ($null -eq $parsed) { return @() }
        return @($parsed)
    }
    catch {
        Write-OptimizerLog "Could not read snapshot '$Path': $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-SnapshotCategories {
    if (-not $Script:SnapshotDir -or -not (Test-Path $Script:SnapshotDir)) { return @() }
    Get-ChildItem -Path $Script:SnapshotDir -Filter '*.json' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName }
}

function Undo-OptimizationCategory {
    <#
        Replays the most recent snapshot for a category in reverse, restoring
        prior registry values and service start types. Appx package removal
        and disk cleanup are not reversible this way; use System Restore for
        those (see Show-SystemRestore).
    #>
    param([Parameter(Mandatory)][string]$Category)

    $file = Join-Path $Script:SnapshotDir "$Category.json"
    if (-not (Test-Path $file)) {
        Write-OptimizerLog "No snapshot found for category '$Category'" -Level Warn
        return @()
    }

    $entries = Read-SnapshotFile -Path $file
    $results = New-Object System.Collections.Generic.List[object]
    if ($entries.Count -eq 0) {
        Write-OptimizerLog "Snapshot for '$Category' was empty or unreadable" -Level Warn
        return @([pscustomobject]@{ Name = "No usable snapshot data for '$Category'"; Success = $false })
    }

    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        try {
            if ($null -eq $e -or -not ($e.PSObject.Properties.Name -contains 'Kind')) {
                $results.Add([pscustomobject]@{ Name = "Skipped malformed snapshot entry #$i"; Success = $false })
                continue
            }
            switch ($e.Kind) {
                'Registry' {
                    if ($e.Existed) {
                        New-ItemProperty -Path $e.Path -Name $e.Name -PropertyType $e.Type -Value $e.OldValue -Force -ErrorAction Stop | Out-Null
                        $detail = "Restored $($e.Path)\$($e.Name) = $($e.OldValue)"
                    }
                    else {
                        Remove-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue
                        $detail = "Removed $($e.Path)\$($e.Name) (did not exist before)"
                    }
                    $results.Add([pscustomobject]@{ Name = $detail; Success = $true })
                }
                'Service' {
                    Set-Service -Name $e.Name -StartupType $e.OldStartType -ErrorAction Stop
                    $results.Add([pscustomobject]@{ Name = "Restored service $($e.Name) to $($e.OldStartType)"; Success = $true })
                }
                'ScheduledTask' {
                    if ($e.WasEnabled) {
                        $parts = Split-TaskPath -TaskPath $e.TaskPath
                        Enable-ScheduledTask -TaskPath $parts.Folder -TaskName $parts.Name -ErrorAction Stop | Out-Null
                        $results.Add([pscustomobject]@{ Name = "Re-enabled scheduled task $($e.TaskPath)"; Success = $true })
                    }
                    else {
                        $results.Add([pscustomobject]@{ Name = "Task $($e.TaskPath) was already disabled; left as-is"; Success = $true })
                    }
                }
            }
            # Only Registry/Service entries carry Path/Name and only
            # ScheduledTask entries carry TaskPath; under StrictMode reading the
            # wrong one throws, so pick the field that exists for this Kind.
            $label = if ($e.Kind -eq 'ScheduledTask') { $e.TaskPath } else { "$($e.Path)\$($e.Name)" }
            Write-OptimizerLog "UNDO $($e.Kind): $label" -Level Success
        }
        catch {
            Write-OptimizerLog "UNDO FAILED for entry $($i): $($_.Exception.Message)" -Level Error
            $results.Add([pscustomobject]@{ Name = "Undo failed: $($_.Exception.Message)"; Success = $false })
        }
    }

    Remove-Item $file -Force -ErrorAction SilentlyContinue
    Clear-CategoryStatusCache
    return $results
}

# ---------------------------------------------------------------------------
# Primitive tweak helpers (each logs, snapshots, and honours -WhatIf)
# ---------------------------------------------------------------------------

function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('DWord', 'String', 'Binary', 'MultiString', 'QWord')][string]$Type,
        [Parameter(Mandatory)]$Value,
        [string]$Category
    )
    $label = "$Path\$Name"
    if (-not $PSCmdlet.ShouldProcess($label, "Set to '$Value'")) {
        return [pscustomobject]@{ Name = "Set $label = $Value (WhatIf)"; Success = $true }
    }
    try {
        $existed = $false
        $old = $null
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name)) {
                $old = $prop.$Name
                $existed = $true
            }
        }
        else {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        if ($Category) {
            Add-SnapshotEntry -Category $Category -Entry ([pscustomobject]@{
                Kind = 'Registry'; Path = $Path; Name = $Name; Type = $Type; OldValue = $old; Existed = $existed
            })
        }
        New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
        Write-OptimizerLog "SET  $label = $Value" -Level Success
        return [pscustomobject]@{ Name = "$label = $Value"; Success = $true }
    }
    catch {
        Write-OptimizerLog "FAIL $label : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ Name = "$label ($($_.Exception.Message))"; Success = $false }
    }
}

function Get-RegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (-not (Test-Path $Path)) { return $null }
    $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $prop) { return $null }
    return $prop.$Name
}

function Set-ServiceState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Automatic', 'Manual', 'Disabled')][string]$StartupType,
        [switch]$Stop,
        [string]$Category
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [pscustomobject]@{ Name = "Service $Name not present (skipped)"; Success = $true }
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Set startup type to $StartupType")) {
        return [pscustomobject]@{ Name = "Service $Name -> $StartupType (WhatIf)"; Success = $true }
    }
    try {
        if ($Category) {
            Add-SnapshotEntry -Category $Category -Entry ([pscustomobject]@{
                Kind = 'Service'; Name = $Name; OldStartType = $svc.StartType.ToString()
            })
        }
        if ($Stop -and $svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        Write-OptimizerLog "SVC  $Name -> $StartupType" -Level Success
        return [pscustomobject]@{ Name = "Service $Name -> $StartupType"; Success = $true }
    }
    catch {
        Write-OptimizerLog "FAIL service $Name : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ Name = "Service $Name ($($_.Exception.Message))"; Success = $false }
    }
}

function Disable-ScheduledTaskSafe {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TaskPath, [string]$Category)

    $parts = Split-TaskPath -TaskPath $TaskPath
    $folder = $parts.Folder
    $name = $parts.Name

    $task = Get-ScheduledTask -TaskName $name -TaskPath $folder -ErrorAction SilentlyContinue
    if (-not $task) {
        return [pscustomobject]@{ Name = "Task $TaskPath not present (skipped)"; Success = $true }
    }
    if (-not $PSCmdlet.ShouldProcess($TaskPath, 'Disable scheduled task')) {
        return [pscustomobject]@{ Name = "Task $TaskPath (WhatIf)"; Success = $true }
    }
    try {
        if ($Category) {
            Add-SnapshotEntry -Category $Category -Entry ([pscustomobject]@{
                Kind = 'ScheduledTask'; TaskPath = $TaskPath; WasEnabled = ($task.State -ne 'Disabled')
            })
        }
        Disable-ScheduledTask -TaskName $name -TaskPath $folder -ErrorAction Stop | Out-Null
        Write-OptimizerLog "TASK disabled: $TaskPath" -Level Success
        return [pscustomobject]@{ Name = "Task $TaskPath disabled"; Success = $true }
    }
    catch {
        Write-OptimizerLog "FAIL task $TaskPath : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ Name = "Task $TaskPath ($($_.Exception.Message))"; Success = $false }
    }
}

function Remove-AppxPackageSafe {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$PackageName)

    if (-not $PSCmdlet.ShouldProcess($PackageName, 'Remove appx package (all users + provisioned image)')) {
        return [pscustomobject]@{ Name = "$PackageName (WhatIf)"; Success = $true }
    }
    $removedAny = $false
    try {
        $installed = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
        if ($installed) {
            $installed | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
            $removedAny = $true
        }
        $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $PackageName }
        if ($provisioned) {
            $provisioned | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            $removedAny = $true
        }
        $msg = if ($removedAny) { "$PackageName removed" } else { "$PackageName not present (skipped)" }
        Write-OptimizerLog "APP  $msg" -Level Success
        return [pscustomobject]@{ Name = $msg; Success = $true }
    }
    catch {
        Write-OptimizerLog "FAIL removing $PackageName : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ Name = "$PackageName ($($_.Exception.Message))"; Success = $false }
    }
}

# ---------------------------------------------------------------------------
# Category catalogue (single source of truth for both UIs)
# ---------------------------------------------------------------------------

function Get-OptimizerCategories {
    @(
        [pscustomobject]@{ Id = 'RestorePoint'; Name = 'Create restore point'; Description = 'Checkpoint via System Protection so changes can be rolled back.'; Destructive = $false; Reversible = 'System Restore' }
        [pscustomobject]@{ Id = 'ConsumerApps'; Name = 'Remove consumer apps'; Description = 'Uninstalls inbox UWP apps (News, Xbox suite, Spotify, TikTok, etc.) for all users and provisioned images.'; Destructive = $true; Reversible = 'Not reversible (reinstall via Store)' }
        [pscustomobject]@{ Id = 'Telemetry'; Name = 'Disable telemetry'; Description = 'Disables DiagTrack/CEIP services and scheduled tasks, sets telemetry policy to minimum.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'Performance'; Name = 'Performance + touch tweaks'; Description = 'High performance power plan, disables transparency/throttling, keeps touch/pen services intact.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'OemPromos'; Name = 'Remove OEM promo apps'; Description = 'Removes common OEM-bundled promo packages if present on this device image.'; Destructive = $true; Reversible = 'Not reversible (reinstall via Store)' }
        [pscustomobject]@{ Id = 'BackgroundServices'; Name = 'Trim background services'; Description = 'Disables SysMain/MapsBroker/TrkWks, sets Search indexing to manual, disables Start suggestions.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'DiskCleanup'; Name = 'Free disk space'; Description = 'Disables hibernation, clears temp folders and the Windows Update cache, runs DISM component cleanup.'; Destructive = $true; Reversible = 'Partially reversible (hibernation only)' }
        [pscustomobject]@{ Id = 'WidgetsChat'; Name = 'Disable Widgets + Teams Chat'; Description = 'Hides Widgets, Teams Chat, and the Copilot taskbar button.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'Animations'; Name = 'Disable animations + visual effects'; Description = 'Turns off window/taskbar animations, Aero Peek, and touch-keyboard autocorrect/prediction for max responsiveness.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'Startup'; Name = 'Optimize startup'; Description = 'Disables Fast Startup, trims non-essential scheduled tasks and Xbox services, enables memory compression.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'GameDvr'; Name = 'Disable Game Bar capture'; Description = 'Turns off Xbox Game Bar background recording, which costs CPU on every device even without Xbox apps.'; Destructive = $false; Reversible = 'Undo available' }
        [pscustomobject]@{ Id = 'ReservedStorage'; Name = 'Disable reserved storage'; Description = 'Reclaims the ~7GB Windows reserves for updates - the biggest single space win on a 64GB eMMC device.'; Destructive = $false; Reversible = 'Re-enable via Set-WindowsReservedStorageState' }
        [pscustomobject]@{ Id = 'StorageSense'; Name = 'Enable Storage Sense'; Description = 'Schedules automatic temp/recycle-bin cleanup every 30 days so a small eMMC disk stays usable long-term.'; Destructive = $false; Reversible = 'Undo available' }
    )
}

# ---------------------------------------------------------------------------
# Category implementations
# ---------------------------------------------------------------------------

function New-OptimizerRestorePoint {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('System', 'Create restore point')) {
        return @([pscustomobject]@{ Name = 'Restore point (WhatIf)'; Success = $true })
    }
    try {
        Checkpoint-Computer -Description 'TouchOptimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-OptimizerLog 'Restore point created' -Level Success
        return @([pscustomobject]@{ Name = 'Restore point created'; Success = $true })
    }
    catch {
        Write-OptimizerLog "Restore point failed: $($_.Exception.Message)" -Level Error
        return @([pscustomobject]@{ Name = "Restore point failed: $($_.Exception.Message)"; Success = $false })
    }
}

function Show-SystemRestore {
    Write-OptimizerLog 'Launching System Restore (rstrui.exe)' -Level Info
    Start-Process 'rstrui.exe'
}

$Script:ConsumerAppList = @(
    'Microsoft.BingNews', 'Microsoft.BingFinance', 'Microsoft.BingWeather', 'Microsoft.GetHelp',
    'Microsoft.Getstarted', 'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.MixedReality.Portal',
    'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.SkypeApp', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo', 'MicrosoftWindows.Client.WebExperience', 'Clipchamp.Clipchamp',
    'SpotifyAB.SpotifyMusic', 'BytedancePte.Ltd.TikTok', 'Facebook.Facebook', 'Disney.37853FC22B2CE',
    'Microsoft.YourPhone', 'MicrosoftCorporationII.QuickAssist', 'Microsoft.Whiteboard',
    'Microsoft.WindowsSoundRecorder', 'Microsoft.WindowsAlarms', 'MicrosoftTeams', 'Microsoft.OneDriveSync'
)

$Script:OemPromoList = @('EclipseManager', 'ActiproSoftwareLLC.562882FEEB491', 'DellInc.PartnerPromo')

function Invoke-ConsumerAppRemoval {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    # Delegate the ShouldProcess decision to Remove-AppxPackageSafe rather than
    # gating it here too, which would emit the WhatIf notice twice per package.
    $Script:ConsumerAppList | ForEach-Object {
        Remove-AppxPackageSafe -PackageName $_ -WhatIf:$WhatIfPreference
    }
}

function Invoke-OemPromoRemoval {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $Script:OemPromoList | ForEach-Object {
        Remove-AppxPackageSafe -PackageName $_ -WhatIf:$WhatIfPreference
    }
}

function Invoke-TelemetryDisable {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($svc in 'DiagTrack', 'dmwappushservice', 'RetailDemo', 'RemoteRegistry', 'WerSvc', 'RemoteAccess') {
        $results.Add((Set-ServiceState -Name $svc -StartupType Disabled -Stop -Category 'Telemetry' -WhatIf:$WhatIfPreference))
    }
    foreach ($task in
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenario',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    ) {
        $results.Add((Disable-ScheduledTaskSafe -TaskPath $task -Category 'Telemetry' -WhatIf:$WhatIfPreference))
    }

    $regValues = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC'; Name = 'PreventHandwritingDataSharing'; Type = 'DWord'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsRunInBackground'; Type = 'DWord'; Value = 2 }
    )
    foreach ($r in $regValues) {
        $results.Add((Set-RegistryValue @r -Category 'Telemetry' -WhatIf:$WhatIfPreference))
    }
    return $results
}

function Invoke-PerformanceTweaks {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]

    $profile = Get-DeviceProfile

    # Forcing High Performance on a fanless tablet pins the CPU out of its low
    # power states: it thermally throttles and sustained performance drops,
    # while battery life falls off a cliff. Balanced is genuinely faster there.
    if ($profile.IsFanlessTablet) {
        $results.Add((Write-SkippedTweak -What 'Power plan -> High performance' `
            -Reason 'fanless/battery device - forcing High Performance causes thermal throttling; leaving Balanced'))
    }
    elseif ($PSCmdlet.ShouldProcess('SCHEME_MIN', 'Set active power plan')) {
        try { powercfg /setactive SCHEME_MIN | Out-Null; $results.Add([pscustomobject]@{ Name = 'Power plan -> High performance'; Success = $true }) }
        catch { $results.Add([pscustomobject]@{ Name = "Power plan change failed: $($_.Exception.Message)"; Success = $false }) }
    }
    else { $results.Add([pscustomobject]@{ Name = 'Power plan -> High performance (WhatIf)'; Success = $true }) }

    # Power Throttling de-prioritises *background* work on modern low-TDP CPUs.
    # Turning it off on a 2-core tablet lets background apps fight the
    # foreground for both cores and burns battery for no responsiveness gain.
    if ($profile.HasBattery) {
        $results.Add((Write-SkippedTweak -What 'Disable CPU power throttling' `
            -Reason 'battery device - throttling protects foreground responsiveness and battery'))
    }
    else {
        $results.Add((Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Type DWord -Value 1 -Category 'Performance' -WhatIf:$WhatIfPreference))
    }

    # Superfetch/SysMain is a win on eMMC and on low-RAM machines - it exists
    # precisely to mask slow storage. Only disable it on fast storage.
    if ($profile.IsSlowStorage -or $profile.IsLowMemory) {
        $results.Add((Write-SkippedTweak -What 'Disable Superfetch' `
            -Reason "$($profile.SystemDiskMedia) storage / $($profile.RamGB)GB RAM - prefetching helps here"))
    }
    else {
        $results.Add((Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'EnableSuperfetch' -Type DWord -Value 0 -Category 'Performance' -WhatIf:$WhatIfPreference))
    }

    $regValues = @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnablePrefetcher'; Type = 'DWord'; Value = 2 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; Value = 2 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord'; Value = 4294967295 }
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'DisableAcrylicBackgroundOnLogon'; Type = 'DWord'; Value = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'EnableAutoTray'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'MenuShowDelay'; Type = 'String'; Value = '0' }
        @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseHoverTime'; Type = 'String'; Value = '10' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control'; Name = 'WaitToKillServiceTimeout'; Type = 'String'; Value = '2000' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WaitToKillAppTimeout'; Type = 'String'; Value = '2000' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'LowLevelHooksTimeout'; Type = 'String'; Value = '1000' }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'HungAppTimeout'; Type = 'String'; Value = '1000' }
        @{ Path = 'HKCU:\Control Panel\Pen'; Name = 'PenTapFeedbackVisualization'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Control Panel\Cursors'; Name = 'ContactVisualization'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Control Panel\Cursors'; Name = 'GestureVisualization'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace'; Name = 'PenWorkspaceButtonDesiredVisibility'; Type = 'DWord'; Value = 0 }
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'Performance' -WhatIf:$WhatIfPreference)) }

    # Keep touch keyboard and handwriting services available on demand.
    foreach ($svc in 'TabletInputService', 'TextInputManagementService') {
        $results.Add((Set-ServiceState -Name $svc -StartupType Manual -Category 'Performance' -WhatIf:$WhatIfPreference))
    }
    return $results
}

function Invoke-BackgroundServiceTrim {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]

    $profile = Get-DeviceProfile

    # SysMain backs both Superfetch *and* memory compression. On a 4GB eMMC
    # tablet, killing it costs more than it saves - and the Startup category
    # later tries to enable memory compression, which needs this service
    # running. Disabling it here would silently make that step a no-op.
    if ($profile.IsSlowStorage -or $profile.IsLowMemory) {
        $results.Add((Write-SkippedTweak -What 'Disable SysMain' `
            -Reason "$($profile.SystemDiskMedia) storage / $($profile.RamGB)GB RAM - SysMain provides memory compression and masks slow storage"))
    }
    else {
        $results.Add((Set-ServiceState -Name 'SysMain' -StartupType Disabled -Stop -Category 'BackgroundServices' -WhatIf:$WhatIfPreference))
    }

    foreach ($svc in 'MapsBroker', 'TrkWks') {
        $results.Add((Set-ServiceState -Name $svc -StartupType Disabled -Stop -Category 'BackgroundServices' -WhatIf:$WhatIfPreference))
    }
    $results.Add((Set-ServiceState -Name 'WSearch' -StartupType Manual -Stop -Category 'BackgroundServices' -WhatIf:$WhatIfPreference))

    $regValues = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'CortanaConsent'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Type = 'DWord'; Value = 0 }
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'BackgroundServices' -WhatIf:$WhatIfPreference)) }

    foreach ($key in 'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SystemPaneSuggestionsEnabled') {
        $results.Add((Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name $key -Type DWord -Value 0 -Category 'BackgroundServices' -WhatIf:$WhatIfPreference))
    }
    return $results
}

function Clear-TempFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TargetPath)
    if (-not (Test-Path $TargetPath)) { return [pscustomobject]@{ Name = "$TargetPath (not present)"; Success = $true } }
    if (-not $PSCmdlet.ShouldProcess($TargetPath, 'Delete contents')) {
        return [pscustomobject]@{ Name = "$TargetPath (WhatIf)"; Success = $true }
    }
    try {
        Get-ChildItem -Path $TargetPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-OptimizerLog "Cleared $TargetPath" -Level Success
        return [pscustomobject]@{ Name = "Cleared $TargetPath"; Success = $true }
    }
    catch {
        Write-OptimizerLog "Failed clearing $TargetPath : $($_.Exception.Message)" -Level Error
        return [pscustomobject]@{ Name = "$TargetPath ($($_.Exception.Message))"; Success = $false }
    }
}

function Invoke-DiskCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]

    $results.Add((Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Type DWord -Value 0 -Category 'DiskCleanup' -WhatIf:$WhatIfPreference))
    if ($PSCmdlet.ShouldProcess('Hibernation', 'Disable (powercfg /h off)')) {
        # 2>$null only covers stderr; native stdout would otherwise land in this
        # function's output stream and be rendered as a bogus result row.
        powercfg /h off 2>$null | Out-Null
        Write-OptimizerLog 'Hibernation disabled' -Level Success
        $results.Add([pscustomobject]@{ Name = 'Hibernation disabled'; Success = $true })
    }

    # %TEMP% and %LOCALAPPDATA%\Temp are normally the same folder - dedupe so
    # it is not scanned twice (it is the slowest step on eMMC).
    $tempPaths = @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:SystemRoot\Temp") |
        Where-Object { $_ } |
        ForEach-Object { $_.TrimEnd('\') } |
        Select-Object -Unique
    foreach ($path in $tempPaths) {
        $results.Add((Clear-TempFolder -TargetPath $path -WhatIf:$WhatIfPreference))
    }

    if ($PSCmdlet.ShouldProcess('SoftwareDistribution\Download', 'Clear Windows Update cache')) {
        try {
            Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            $wu = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $wu) { Remove-Item "$wu\*" -Recurse -Force -ErrorAction SilentlyContinue }
            Start-Service wuauserv, bits -ErrorAction SilentlyContinue
            $results.Add([pscustomobject]@{ Name = 'Windows Update cache cleared'; Success = $true })
        }
        catch {
            $results.Add([pscustomobject]@{ Name = "WU cache clear failed: $($_.Exception.Message)"; Success = $false })
        }
    }

    if ($PSCmdlet.ShouldProcess('Component Store', 'DISM /StartComponentCleanup')) {
        try {
            $out = & "$env:SystemRoot\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup 2>&1
            $out | Out-String | Add-Content -Path (Get-OptimizerLogPath) -Encoding utf8
            $results.Add([pscustomobject]@{ Name = 'DISM component cleanup complete'; Success = $true })
        }
        catch {
            $results.Add([pscustomobject]@{ Name = "DISM cleanup failed: $($_.Exception.Message)"; Success = $false })
        }
    }
    return $results
}

function Invoke-WidgetsChatDisable {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]
    $regValues = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarDa'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarChatEnabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Type = 'DWord'; Value = 0 }
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'WidgetsChat' -WhatIf:$WhatIfPreference)) }
    $results.Add((Disable-ScheduledTaskSafe -TaskPath '\Microsoft\Windows\Windows Copilot\CopilotActivation' -Category 'WidgetsChat' -WhatIf:$WhatIfPreference))
    return $results
}

function Invoke-AnimationDisable {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]
    $regValues = @(
        @{ Path = 'HKCU:\Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Type = 'String'; Value = '0' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAnimations'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; Value = 3 }
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'UserPreferencesMask'; Type = 'Binary'; Value = ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\DWM'; Name = 'EnableAeroPeek'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\DWM'; Name = 'AlwaysHibernateThumbnails'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewAlphaSelect'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewShadow'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarMn'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DisallowShaking'; Type = 'DWord'; Value = 1 }
        @{ Path = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnableAutocorrection'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnableSpellchecking'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnableTextPrediction'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnablePredictionSpaceInsertion'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Wisp\Pen\SysEventParameters'; Name = 'Flickscustomized'; Type = 'DWord'; Value = 1 }
        @{ Path = 'HKCU:\Software\Microsoft\Wisp\Pen\SysEventParameters'; Name = 'FlicksEnabled'; Type = 'DWord'; Value = 0 }
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'Animations' -WhatIf:$WhatIfPreference)) }
    return $results
}

function Invoke-StartupOptimization {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]
    $profile = Get-DeviceProfile

    $results.Add((Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name 'StartupDelayInMSec' -Type DWord -Value 0 -Category 'Startup' -WhatIf:$WhatIfPreference))

    foreach ($task in
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
        '\Microsoft\Windows\Maps\MapsUpdateTask',
        '\Microsoft\Windows\Maps\MapsToastTask',
        '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask'
    ) {
        $results.Add((Disable-ScheduledTaskSafe -TaskPath $task -Category 'Startup' -WhatIf:$WhatIfPreference))
    }

    if ($PSCmdlet.ShouldProcess('Sleep timeout', 'Hide + zero out sleep power setting')) {
        powercfg -attributes SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 -ATTRIB_HIDE 2>$null | Out-Null
        powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 2>$null | Out-Null
        powercfg -setdcvalueindex SCHEME_CURRENT SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 2>$null | Out-Null
        $results.Add([pscustomobject]@{ Name = 'Sleep timeout tweaked'; Success = $true })
    }

    if ($PSCmdlet.ShouldProcess('Optional Windows features', 'Disable Printing-XPSServices, WorkFolders-Client, FaxServicesClientPackage')) {
        foreach ($feature in 'Printing-XPSServices-Features', 'WorkFolders-Client', 'FaxServicesClientPackage') {
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop | Out-Null
                $results.Add([pscustomobject]@{ Name = "Feature $feature disabled"; Success = $true })
            }
            catch {
                $results.Add([pscustomobject]@{ Name = "Feature $feature ($($_.Exception.Message))"; Success = $false })
            }
        }
    }

    foreach ($svc in 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc') {
        $results.Add((Set-ServiceState -Name $svc -StartupType Disabled -Stop -Category 'Startup' -WhatIf:$WhatIfPreference))
    }

    # Memory compression is served by SysMain; if a previous run disabled that
    # service this silently does nothing, so say so rather than reporting OK.
    $sysMainState = Get-ServiceStartTypeSafe -Name 'SysMain'
    if ($sysMainState -eq 'Disabled') {
        $results.Add((Write-SkippedTweak -What 'Enable memory compression' `
            -Reason 'SysMain is disabled, which memory compression depends on - re-enable SysMain first'))
    }
    elseif ($PSCmdlet.ShouldProcess('Memory compression', 'Enable-MMAgent -MemoryCompression')) {
        try { Enable-MMAgent -MemoryCompression -ErrorAction Stop | Out-Null; $results.Add([pscustomobject]@{ Name = 'Memory compression enabled'; Success = $true }) }
        catch { $results.Add([pscustomobject]@{ Name = "Memory compression ($($_.Exception.Message))"; Success = $false }) }
    }

    # DisablePagingExecutive pins the kernel in RAM. That is a sensible tweak on
    # a 16GB desktop and a bad one on a 4GB tablet, where it consumes memory the
    # system needs for the foreground app.
    if ($profile.IsLowMemory) {
        $results.Add((Write-SkippedTweak -What 'Keep kernel resident in RAM (DisablePagingExecutive)' `
            -Reason "$($profile.RamGB)GB RAM - would consume memory needed by foreground apps"))
    }
    else {
        $results.Add((Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Type DWord -Value 1 -Category 'Startup' -WhatIf:$WhatIfPreference))
    }
    $results.Add((Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'LargeSystemCache' -Type DWord -Value 0 -Category 'Startup' -WhatIf:$WhatIfPreference))
    return $results
}

function Invoke-GameDvrDisable {
    <#
        Xbox Game Bar's background capture runs on every device, not just ones
        with Xbox apps installed, and costs real CPU on a 2-core part. The
        Startup category disables the Xbox *services*; this disables capture.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]
    $regValues = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_FSEBehaviorMode'; Type = 'DWord'; Value = 2 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Type = 'DWord'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'ShowStartupPanel'; Type = 'DWord'; Value = 0 }
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'GameDvr' -WhatIf:$WhatIfPreference)) }
    return $results
}

function Invoke-ReservedStorageDisable {
    <#
        Windows reserves ~7GB for updates. On the 64GB eMMC Surface Go that is
        over a tenth of the disk, and it is the single biggest space win
        available. Only offered where it actually matters.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]

    if (-not (Get-Command Set-WindowsReservedStorageState -ErrorAction SilentlyContinue)) {
        $results.Add((Write-SkippedTweak -What 'Disable reserved storage' -Reason 'cmdlet not available on this Windows build'))
        return $results
    }
    if ($PSCmdlet.ShouldProcess('Reserved storage', 'Disable')) {
        try {
            Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null
            Write-OptimizerLog 'Reserved storage disabled' -Level Success
            $results.Add([pscustomobject]@{ Name = 'Reserved storage disabled (frees ~7GB)'; Success = $true })
        }
        catch {
            # Fails while an update is pending - that is expected, not a crash.
            $results.Add([pscustomobject]@{ Name = "Reserved storage: $($_.Exception.Message)"; Success = $false })
        }
    }
    else { $results.Add([pscustomobject]@{ Name = 'Reserved storage disabled (WhatIf)'; Success = $true }) }
    return $results
}

function Invoke-StorageSenseEnable {
    <#
        The opposite of a debloat tweak: on a small eMMC disk, having Windows
        clean up automatically is what keeps the device usable months later.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $results = New-Object System.Collections.Generic.List[object]
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    $regValues = @(
        @{ Path = $base; Name = '01'; Type = 'DWord'; Value = 1 }    # Storage Sense on
        @{ Path = $base; Name = '04'; Type = 'DWord'; Value = 1 }    # clean temp files
        @{ Path = $base; Name = '08'; Type = 'DWord'; Value = 1 }    # clean recycle bin
        @{ Path = $base; Name = '32'; Type = 'DWord'; Value = 30 }   # run every 30 days
        @{ Path = $base; Name = '256'; Type = 'DWord'; Value = 30 }  # recycle bin age (days)
    )
    foreach ($r in $regValues) { $results.Add((Set-RegistryValue @r -Category 'StorageSense' -WhatIf:$WhatIfPreference)) }
    return $results
}

# ---------------------------------------------------------------------------
# Dispatch table + status
# ---------------------------------------------------------------------------

$Script:CategoryHandlers = @{
    RestorePoint       = { New-OptimizerRestorePoint }
    ConsumerApps       = { Invoke-ConsumerAppRemoval }
    Telemetry          = { Invoke-TelemetryDisable }
    Performance        = { Invoke-PerformanceTweaks }
    OemPromos          = { Invoke-OemPromoRemoval }
    BackgroundServices = { Invoke-BackgroundServiceTrim }
    DiskCleanup        = { Invoke-DiskCleanup }
    WidgetsChat        = { Invoke-WidgetsChatDisable }
    Animations         = { Invoke-AnimationDisable }
    Startup            = { Invoke-StartupOptimization }
    GameDvr            = { Invoke-GameDvrDisable }
    ReservedStorage    = { Invoke-ReservedStorageDisable }
    StorageSense       = { Invoke-StorageSenseEnable }
}

function Invoke-OptimizerCategory {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    if (-not $Script:CategoryHandlers.ContainsKey($Id)) {
        throw "Unknown category '$Id'"
    }
    Write-OptimizerLog "=== Running category: $Id ===" -Level Info
    try { & $Script:CategoryHandlers[$Id] }
    finally {
        # State changed underneath the cached probes, so force a re-read next
        # time the UI asks. A dry run changes nothing but invalidating anyway
        # is cheap and keeps this correct if a handler ever half-applies.
        Clear-CategoryStatusCache
    }
}

$Script:StatusCache = @{}

function Clear-CategoryStatusCache { $Script:StatusCache = @{} }

function Get-CategoryStatus {
    <#
        Cheap, representative markers per category so the UI can show
        Applied / Partial / Not applied without re-running every tweak.

        Results are cached: probing all categories costs ~300ms on a fast
        desktop (Get-AppxPackage alone is ~135ms), and both UIs redraw their
        checklist on every keystroke/click. On the 2-core devices this tool
        targets that uncached cost turns into seconds of lag per toggle.
        Call Clear-CategoryStatusCache after applying or undoing tweaks.
    #>
    param([Parameter(Mandatory)][string]$Id, [switch]$Refresh)

    if (-not $Refresh -and $Script:StatusCache.ContainsKey($Id)) {
        return $Script:StatusCache[$Id]
    }
    $result = Get-CategoryStatusUncached -Id $Id
    $Script:StatusCache[$Id] = $result
    return $result
}

function Get-CategoryStatusUncached {
    param([Parameter(Mandatory)][string]$Id)

    switch ($Id) {
        'Telemetry' {
            $svc = Get-ServiceStartTypeSafe -Name 'DiagTrack'
            $reg = Get-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
            if ($svc -eq 'Disabled' -and $reg -eq 0) { return 'Applied' }
            if ($svc -eq 'Disabled' -or $reg -eq 0) { return 'Partial' }
            return 'NotApplied'
        }
        'Performance' {
            $val = Get-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency'
            if ($val -eq 0) { return 'Applied' }; return 'NotApplied'
        }
        'BackgroundServices' {
            # SysMain is deliberately left running on low-RAM/slow-storage
            # devices, so key the status off a marker that always applies.
            $trk = Get-ServiceStartTypeSafe -Name 'TrkWks'
            $bing = Get-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled'
            if ($trk -eq 'Disabled' -and $bing -eq 0) { return 'Applied' }
            if ($trk -eq 'Disabled' -or $bing -eq 0) { return 'Partial' }
            return 'NotApplied'
        }
        'WidgetsChat' {
            $val = Get-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa'
            if ($val -eq 0) { return 'Applied' }; return 'NotApplied'
        }
        'Animations' {
            $val = Get-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
            if ($val -eq 3) { return 'Applied' }; return 'NotApplied'
        }
        'Startup' {
            # Keyed on Fast Startup, which only this category touches.
            $val = Get-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
            $delay = Get-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec'
            if ($val -eq 0 -and $delay -eq 0) { return 'Applied' }
            if ($val -eq 0 -or $delay -eq 0) { return 'Partial' }
            return 'NotApplied'
        }
        'DiskCleanup' {
            # Must NOT reuse HiberbootEnabled - the Startup category sets that
            # too, which made this row report "Applied" after a startup-only
            # run. hiberfil.sys is the marker unique to 'powercfg /h off'.
            if (-not (Test-Path "$env:SystemDrive\hiberfil.sys")) { return 'Applied' }
            return 'NotApplied'
        }
        'ConsumerApps' {
            $found = Get-AppxPackage -Name 'Microsoft.ZuneMusic' -ErrorAction SilentlyContinue
            if (-not $found) { return 'Applied' }; return 'NotApplied'
        }
        'GameDvr' {
            $val = Get-RegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
            if ($val -eq 0) { return 'Applied' }; return 'NotApplied'
        }
        'ReservedStorage' {
            if (-not (Get-Command Get-WindowsReservedStorageState -ErrorAction SilentlyContinue)) { return 'Unknown' }
            try {
                $state = (Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState
                if ($state -eq 'Disabled') { return 'Applied' }
                return 'NotApplied'
            }
            catch { return 'Unknown' }
        }
        'StorageSense' {
            $val = Get-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01'
            if ($val -eq 1) { return 'Applied' }; return 'NotApplied'
        }
        'OemPromos' { return 'Unknown' }
        'RestorePoint' { return 'ActionOnly' }
        default { return 'Unknown' }
    }
}

Export-ModuleMember -Function * -Variable ConsumerAppList, OemPromoList
