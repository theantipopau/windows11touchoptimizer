#requires -Version 5.1
<#
    TouchOptimizer.ps1
    Console front-end for the Windows 11 Touchscreen Device Optimiser.
    Multi-select checklist over TouchOptimizer.psm1 — replaces the old
    monolithic .bat menu.
#>

param()

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptRoot 'TouchOptimizer.psm1') -Force

Assert-Elevation -ScriptPath $MyInvocation.MyCommand.Path
Initialize-OptimizerLog -ScriptRoot $ScriptRoot | Out-Null

$Host.UI.RawUI.WindowTitle = 'Windows 11 Touchscreen Device Optimiser'

$Categories = Get-OptimizerCategories | Where-Object { $_.Id -ne 'RestorePoint' }
$Selected = @{}
foreach ($c in $Categories) { $Selected[$c.Id] = $false }

$RecommendedIds = 'ConsumerApps', 'Telemetry', 'Performance', 'StorageSense'

$DeviceProfile = Get-DeviceProfile

function Write-Banner {
    Clear-Host
    Write-Host '========================================================================' -ForegroundColor Magenta
    Write-Host '  Windows 11 Touchscreen Device Optimiser' -ForegroundColor Magenta
    Write-Host '  by Matt Hurley' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------------------' -ForegroundColor Magenta
    $bits = @("$($DeviceProfile.RamGB)GB RAM", "$($DeviceProfile.Cores) cores", $DeviceProfile.SystemDiskMedia)
    if ($DeviceProfile.HasBattery) { $bits += 'battery' }
    Write-Host "  Detected: $($bits -join ' | ')" -ForegroundColor Cyan
    if ($DeviceProfile.IsFanlessTablet -or $DeviceProfile.IsLowMemory -or $DeviceProfile.IsSlowStorage) {
        Write-Host '  Tweaks that would hurt this hardware are auto-skipped.' -ForegroundColor DarkYellow
    }
    Write-Host "  Log: $(Get-OptimizerLogPath)" -ForegroundColor DarkGray
    Write-Host '========================================================================' -ForegroundColor Magenta
}

function Format-Status([string]$status) {
    switch ($status) {
        'Applied' { return @{ Text = 'Applied'; Color = 'Green' } }
        'Partial' { return @{ Text = 'Partial'; Color = 'Yellow' } }
        'NotApplied' { return @{ Text = 'Not applied'; Color = 'DarkGray' } }
        'ActionOnly' { return @{ Text = ''; Color = 'Gray' } }
        default { return @{ Text = '?'; Color = 'DarkGray' } }
    }
}

function Write-Menu {
    Write-Banner
    Write-Host ''
    Write-Host '  Toggle a tweak by number, then G to run your selection.' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $Categories.Count; $i++) {
        $cat = $Categories[$i]
        $mark = if ($Selected[$cat.Id]) { '[x]' } else { '[ ]' }
        $markColor = if ($Selected[$cat.Id]) { 'Yellow' } else { 'White' }
        $status = Format-Status (Get-CategoryStatus -Id $cat.Id)
        $destructive = if ($cat.Destructive) { ' (destructive)' } else { '' }

        Write-Host ("  {0,2}. " -f ($i + 1)) -NoNewline
        Write-Host $mark -ForegroundColor $markColor -NoNewline
        Write-Host (" {0,-32}" -f $cat.Name) -NoNewline
        Write-Host ("{0,-13}" -f $status.Text) -ForegroundColor $status.Color -NoNewline
        Write-Host $destructive -ForegroundColor Red
    }
    Write-Host ''
    Write-Host '  [A] Select all   [N] Select none   [F] Full (select all + run)   [R] Recommended (select + run)' -ForegroundColor DarkCyan
    Write-Host '  [G] Run selected   [W] Dry-run (WhatIf) selected   [P] Create restore point' -ForegroundColor DarkCyan
    Write-Host '  [U] Undo a category   [X] Open System Restore   [I] Show info for a tweak   [Q] Quit' -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-SelectedIds {
    $Categories | Where-Object { $Selected[$_.Id] } | ForEach-Object { $_.Id }
}

function Confirm-Destructive([string[]]$ids) {
    $destructiveCats = $Categories | Where-Object { $_.Id -in $ids -and $_.Destructive }
    if (-not $destructiveCats) { return $true }
    Write-Host ''
    Write-Host '  The following selected steps are DESTRUCTIVE / not fully reversible:' -ForegroundColor Red
    foreach ($d in $destructiveCats) { Write-Host "    - $($d.Name): $($d.Reversible)" -ForegroundColor Red }
    $answer = Read-Host '  Type YES to continue'
    return ($answer -eq 'YES')
}

function Invoke-Selection([string[]]$ids, [switch]$WhatIfMode) {
    if (-not $ids -or $ids.Count -eq 0) {
        Write-Host '  No tweaks selected.' -ForegroundColor Yellow
        return
    }
    if (-not $WhatIfMode -and -not (Confirm-Destructive -ids $ids)) {
        Write-Host '  Cancelled.' -ForegroundColor Yellow
        return
    }
    foreach ($id in $ids) {
        $cat = $Categories | Where-Object { $_.Id -eq $id }
        Write-Host ''
        Write-Host "  >> $($cat.Name)" -ForegroundColor Cyan
        $results = if ($WhatIfMode) { Invoke-OptimizerCategory -Id $id -WhatIf } else { Invoke-OptimizerCategory -Id $id }
        foreach ($r in $results) {
            if ($r.PSObject.Properties.Name -contains 'Skipped' -and $r.Skipped) {
                Write-Host "     [SKIP] $($r.Name)" -ForegroundColor DarkYellow
            }
            elseif ($r.Success) { Write-Host "     [OK]   $($r.Name)" -ForegroundColor Green }
            else { Write-Host "     [FAIL] $($r.Name)" -ForegroundColor Red }
        }
    }
    Write-Host ''
    Write-Host '  Done. Restart your device for all changes to take effect.' -ForegroundColor Cyan
}

do {
    Write-Menu
    $choice = Read-Host '>'
    $choice = $choice.Trim()

    switch -Regex ($choice) {
        '^\d+$' {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $Categories.Count) {
                $id = $Categories[$idx].Id
                $Selected[$id] = -not $Selected[$id]
            }
            else { Write-Host 'Out of range.' -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
        '^[Aa]$' { foreach ($c in $Categories) { $Selected[$c.Id] = $true } }
        '^[Nn]$' { foreach ($c in $Categories) { $Selected[$c.Id] = $false } }
        '^[Gg]$' { Invoke-Selection -ids (Get-SelectedIds); Read-Host 'Press Enter to continue' | Out-Null }
        '^[Ww]$' { Invoke-Selection -ids (Get-SelectedIds) -WhatIfMode; Read-Host 'Press Enter to continue' | Out-Null }
        '^[Ff]$' {
            foreach ($c in $Categories) { $Selected[$c.Id] = $true }
            New-OptimizerRestorePoint | ForEach-Object { if ($_.Success) { Write-Host "  [OK] $($_.Name)" -ForegroundColor Green } else { Write-Host "  [FAIL] $($_.Name)" -ForegroundColor Red } }
            Invoke-Selection -ids (Get-SelectedIds)
            Read-Host 'Press Enter to continue' | Out-Null
        }
        '^[Rr]$' {
            foreach ($c in $Categories) { $Selected[$c.Id] = ($c.Id -in $RecommendedIds) }
            New-OptimizerRestorePoint | ForEach-Object { if ($_.Success) { Write-Host "  [OK] $($_.Name)" -ForegroundColor Green } else { Write-Host "  [FAIL] $($_.Name)" -ForegroundColor Red } }
            Invoke-Selection -ids (Get-SelectedIds)
            Read-Host 'Press Enter to continue' | Out-Null
        }
        '^[Pp]$' {
            New-OptimizerRestorePoint | ForEach-Object { if ($_.Success) { Write-Host "  [OK] $($_.Name)" -ForegroundColor Green } else { Write-Host "  [FAIL] $($_.Name)" -ForegroundColor Red } }
            Read-Host 'Press Enter to continue' | Out-Null
        }
        '^[Uu]$' {
            Write-Host ''
            $available = Get-SnapshotCategories
            if (-not $available) { Write-Host '  No undo snapshots available yet.' -ForegroundColor Yellow }
            else {
                Write-Host "  Categories with undo data: $($available -join ', ')" -ForegroundColor Cyan
                $pick = Read-Host '  Category to undo (exact id, blank to cancel)'
                if ($pick -and $pick -in $available) {
                    $results = Undo-OptimizationCategory -Category $pick
                    foreach ($r in $results) {
                        if ($r.Success) { Write-Host "  [OK] $($r.Name)" -ForegroundColor Green } else { Write-Host "  [FAIL] $($r.Name)" -ForegroundColor Red }
                    }
                }
            }
            Read-Host 'Press Enter to continue' | Out-Null
        }
        '^[Xx]$' {
            $confirm = Read-Host '  Launch System Restore? (Y/N)'
            if ($confirm -match '^[Yy]') { Show-SystemRestore }
        }
        '^[Ii]$' {
            $pick = Read-Host '  Tweak number for details'
            if ($pick -match '^\d+$') {
                $idx = [int]$pick - 1
                if ($idx -ge 0 -and $idx -lt $Categories.Count) {
                    $c = $Categories[$idx]
                    Write-Host ''
                    Write-Host "  $($c.Name)" -ForegroundColor Cyan
                    Write-Host "  $($c.Description)"
                    Write-Host "  Reversible: $($c.Reversible)"
                }
            }
            Read-Host 'Press Enter to continue' | Out-Null
        }
        '^[Qq0]$' { }
        default { Write-Host 'Unknown selection.' -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
} while ($choice -notmatch '^[Qq0]$')

Write-OptimizerLog 'User exited console UI' | Out-Null
Write-Host ''
Write-Host "All done. Review $(Get-OptimizerLogPath) for details." -ForegroundColor Cyan
