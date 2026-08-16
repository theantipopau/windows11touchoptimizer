#requires -Version 5.1
<#
    TouchOptimizerGUI.ps1
    WPF front-end for the Windows 11 Touchscreen Device Optimiser.
    Touch-friendly checklist over TouchOptimizer.psm1, with a background
    runspace so applying tweaks never freezes the window.

    Sizing targets a Surface Go (1800x1200 at 150% scaling = 1200x800 DIP
    landscape, 800x1200 portrait), so the layout collapses to a single column
    below 860 DIP rather than clipping in portrait.
#>

param()

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptRoot 'TouchOptimizer.psm1'
Import-Module $ModulePath -Force

Assert-Elevation -ScriptPath $MyInvocation.MyCommand.Path
$LogPath = Initialize-OptimizerLog -ScriptRoot $ScriptRoot

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows 11 Touchscreen Device Optimiser" Height="700" Width="980"
        MinHeight="520" MinWidth="660" WindowStartupLocation="CenterScreen"
        Background="#1E1E1E">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="MinHeight" Value="44"/>
            <Setter Property="MinWidth" Value="44"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="14,4"/>
            <Setter Property="Margin" Value="0,0,8,8"/>
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E8E8E8"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#E8E8E8"/>
        </Style>
    </Window.Resources>
    <DockPanel LastChildFill="True">
        <Border DockPanel.Dock="Top" Background="#2D2D30" Padding="16,10">
            <StackPanel>
                <TextBlock Text="Windows 11 Touchscreen Device Optimiser" FontSize="19" FontWeight="Bold" Foreground="#FF7BD6"/>
                <TextBlock x:Name="DeviceText" Text="" FontSize="12" Opacity="0.85" Margin="0,2,0,0" TextWrapping="Wrap"/>
                <TextBlock x:Name="LogPathText" Text="" FontSize="11" Opacity="0.55" Margin="0,3,0,0" TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <Border DockPanel.Dock="Top" Background="#252526" Padding="12,8">
            <WrapPanel>
                <Button x:Name="BtnSelectAll" Content="Select all"/>
                <Button x:Name="BtnSelectNone" Content="Select none"/>
                <Button x:Name="BtnRecommended" Content="Recommended"/>
                <Button x:Name="BtnRestorePoint" Content="Restore point" Background="#264F78"/>
                <Button x:Name="BtnRefreshStatus" Content="Refresh status"/>
                <Button x:Name="BtnSystemRestore" Content="System Restore"/>
            </WrapPanel>
        </Border>

        <Border DockPanel.Dock="Bottom" Background="#252526" Padding="12,8">
            <WrapPanel>
                <ComboBox x:Name="ComboUndo" Width="200" Margin="0,0,8,8" MinHeight="40" VerticalContentAlignment="Center"/>
                <Button x:Name="BtnUndo" Content="Undo category"/>
                <TextBlock x:Name="StatusFooter" VerticalAlignment="Center" Margin="12,0,0,8" Opacity="0.7" TextWrapping="Wrap"/>
            </WrapPanel>
        </Border>

        <Grid x:Name="MainGrid">
            <Grid.ColumnDefinitions>
                <ColumnDefinition x:Name="ColLeft" Width="3*"/>
                <ColumnDefinition x:Name="ColRight" Width="2*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition x:Name="RowTop" Height="*"/>
                <RowDefinition x:Name="RowBottom" Height="0"/>
            </Grid.RowDefinitions>

            <ScrollViewer x:Name="TweaksScroller" Grid.Column="0" Grid.Row="0" Margin="12"
                          VerticalScrollBarVisibility="Auto"
                          PanningMode="VerticalOnly" PanningDeceleration="0.001" PanningRatio="1.2"
                          CanContentScroll="False">
                <StackPanel x:Name="TweaksPanel"/>
            </ScrollViewer>

            <DockPanel x:Name="RightPane" Grid.Column="1" Grid.Row="0" Margin="0,12,12,12">
                <ProgressBar x:Name="Progress" DockPanel.Dock="Top" Height="18" Margin="0,0,0,8" Minimum="0" Maximum="1"/>
                <WrapPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
                    <Button x:Name="BtnDryRun" Content="Dry run" Background="#3A3D41" MinWidth="130"/>
                    <Button x:Name="BtnApply" Content="Apply selected" Background="#0E639C" MinWidth="150"/>
                </WrapPanel>
                <TextBox x:Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                         VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"
                         Background="#1B1B1C" Foreground="#D0D0D0" BorderBrush="#3F3F46"/>
            </DockPanel>
        </Grid>
    </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TweaksPanel = $window.FindName('TweaksPanel')
$LogBox = $window.FindName('LogBox')
$Progress = $window.FindName('Progress')
$LogPathText = $window.FindName('LogPathText')
$DeviceText = $window.FindName('DeviceText')
$StatusFooter = $window.FindName('StatusFooter')
$ComboUndo = $window.FindName('ComboUndo')
$RightPane = $window.FindName('RightPane')
$ColRight = $window.FindName('ColRight')
$RowBottom = $window.FindName('RowBottom')

$LogPathText.Text = "Log: $LogPath"

$profile = Get-DeviceProfile
$profileBits = @("$($profile.RamGB)GB RAM", "$($profile.Cores) cores", $profile.SystemDiskMedia)
if ($profile.HasBattery) { $profileBits += 'battery' }
$DeviceText.Text = "Detected: $($profileBits -join ' | ')" +
    $(if ($profile.IsFanlessTablet -or $profile.IsLowMemory -or $profile.IsSlowStorage) {
        '  -  tweaks that would hurt this hardware are auto-skipped (see log)'
      } else { '' })

$Categories = Get-OptimizerCategories | Where-Object { $_.Id -ne 'RestorePoint' }
$RecommendedIds = @('ConsumerApps', 'Telemetry', 'Performance', 'StorageSense')
$Controls = @{}

function New-StatusBrush([string]$status) {
    switch ($status) {
        'Applied' { return 'MediumSeaGreen' }
        'Partial' { return 'Khaki' }
        'NotApplied' { return '#AAAAAA' }
        default { return '#888888' }
    }
}

foreach ($cat in $Categories) {
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = 6
    $border.Background = '#2A2A2C'
    $border.Margin = '0,0,0,8'
    $border.Padding = '12,10'
    # Whole row is a tap target - a bare WPF checkbox glyph is ~13px, far
    # below the ~40px a finger needs.
    $border.Cursor = 'Hand'

    $grid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = 'Auto'
    $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = '*'
    [void]$grid.ColumnDefinitions.Add($col1)
    [void]$grid.ColumnDefinitions.Add($col2)

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Tag = $cat.Id
    $cb.VerticalAlignment = 'Center'
    $cb.Margin = '4,0,14,0'
    # Scale the glyph itself up; MinHeight alone only pads the hit box.
    $scale = New-Object System.Windows.Media.ScaleTransform 1.6, 1.6
    $cb.LayoutTransform = $scale
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)

    $textPanel = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($textPanel, 1)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.FontWeight = 'Bold'
    $title.FontSize = 14
    $title.TextWrapping = 'Wrap'
    $title.Text = $cat.Name + $(if ($cat.Destructive) { '   (destructive)' } else { '' })
    if ($cat.Destructive) { $title.Foreground = '#E06C75' }

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $cat.Description
    $desc.TextWrapping = 'Wrap'
    $desc.Opacity = 0.75
    $desc.Margin = '0,3,0,3'

    $status = New-Object System.Windows.Controls.TextBlock
    $status.Text = 'Status: checking...'
    $status.FontStyle = 'Italic'
    $status.FontSize = 12

    [void]$textPanel.Children.Add($title)
    [void]$textPanel.Children.Add($desc)
    [void]$textPanel.Children.Add($status)

    [void]$grid.Children.Add($cb)
    [void]$grid.Children.Add($textPanel)
    $border.Child = $grid

    # Tapping anywhere on the row toggles it (touch promotes to mouse events),
    # except when the tap landed on the checkbox itself, which handles its own.
    $border.Add_MouseLeftButtonUp({
        param($src, $e)
        $box = $src.Child.Children[0]
        if (-not $e.OriginalSource.Equals($box)) { $box.IsChecked = -not $box.IsChecked }
    }.GetNewClosure())

    [void]$TweaksPanel.Children.Add($border)
    $Controls[$cat.Id] = [pscustomobject]@{ CheckBox = $cb; StatusText = $status; Category = $cat }
}

function Update-StatusDisplay {
    # Always -Refresh: the apply job runs in its own runspace with its own
    # module instance, so cache invalidation there does not reach this one.
    foreach ($id in @($Controls.Keys)) {
        $c = $Controls[$id]
        $s = Get-CategoryStatus -Id $id -Refresh
        $c.StatusText.Text = "Status: $s"
        $c.StatusText.Foreground = New-StatusBrush $s
    }
    $ComboUndo.Items.Clear()
    foreach ($cat in (Get-SnapshotCategories)) { [void]$ComboUndo.Items.Add($cat) }
    if ($ComboUndo.Items.Count -gt 0) { $ComboUndo.SelectedIndex = 0 }
}
Update-StatusDisplay

# Collapse to a single stacked column in portrait / narrow windows so the log
# pane never squeezes the checklist off-screen on a tablet.
$window.Add_SizeChanged({
    $narrow = $window.ActualWidth -lt 860
    if ($narrow) {
        $ColRight.Width = New-Object System.Windows.GridLength 0
        $RowBottom.Height = New-Object System.Windows.GridLength 220, ([System.Windows.GridUnitType]::Pixel)
        [System.Windows.Controls.Grid]::SetColumn($RightPane, 0)
        [System.Windows.Controls.Grid]::SetRow($RightPane, 1)
        [System.Windows.Controls.Grid]::SetColumnSpan($RightPane, 2)
        $RightPane.Margin = '12,0,12,12'
    }
    else {
        $ColRight.Width = New-Object System.Windows.GridLength 2, ([System.Windows.GridUnitType]::Star)
        $RowBottom.Height = New-Object System.Windows.GridLength 0
        [System.Windows.Controls.Grid]::SetColumn($RightPane, 1)
        [System.Windows.Controls.Grid]::SetRow($RightPane, 0)
        [System.Windows.Controls.Grid]::SetColumnSpan($RightPane, 1)
        $RightPane.Margin = '0,12,12,12'
    }
})

function Get-SelectedIds { @($Controls.Keys) | Where-Object { $Controls[$_].CheckBox.IsChecked } }

function Set-UiBusy([bool]$busy) {
    foreach ($btn in 'BtnSelectAll', 'BtnSelectNone', 'BtnRecommended', 'BtnRestorePoint', 'BtnRefreshStatus', 'BtnDryRun', 'BtnApply', 'BtnUndo', 'BtnSystemRestore') {
        $window.FindName($btn).IsEnabled = -not $busy
    }
}

function Start-ApplyJob([string[]]$ids, [bool]$whatIf) {
    if (-not $ids -or $ids.Count -eq 0) {
        $StatusFooter.Text = 'Nothing selected.'
        return
    }
    $destructive = $Categories | Where-Object { $_.Id -in $ids -and $_.Destructive }
    if ($destructive -and -not $whatIf) {
        $names = ($destructive | ForEach-Object { "- $($_.Name): $($_.Reversible)" }) -join "`n"
        $answer = [System.Windows.MessageBox]::Show(
            "The following selected steps are destructive / not fully reversible:`n`n$names`n`nContinue?",
            'Confirm destructive action', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
    }

    $LogBox.Clear()
    $Progress.Maximum = $ids.Count
    $Progress.Value = 0
    Set-UiBusy $true
    $StatusFooter.Text = if ($whatIf) { 'Dry run in progress...' } else { 'Applying...' }

    $sync = [hashtable]::Synchronized(@{
        Queue     = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Done      = $false
        Completed = 0
    })

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('ModulePath', $ModulePath)
    $rs.SessionStateProxy.SetVariable('Ids', $ids)
    $rs.SessionStateProxy.SetVariable('WhatIfMode', $whatIf)
    $rs.SessionStateProxy.SetVariable('LogPath', $LogPath)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        Import-Module $ModulePath -Force
        Set-OptimizerLogPath -LogFile $LogPath
        $allCats = Get-OptimizerCategories
        foreach ($id in $Ids) {
            $cat = $allCats | Where-Object { $_.Id -eq $id }
            $sync.Queue.Enqueue("=== $($cat.Name) ===")
            try {
                $results = if ($WhatIfMode) { Invoke-OptimizerCategory -Id $id -WhatIf } else { Invoke-OptimizerCategory -Id $id }
                foreach ($r in $results) {
                    $prefix = if ($r.PSObject.Properties.Name -contains 'Skipped' -and $r.Skipped) { '[SKIP]' }
                              elseif ($r.Success) { '[OK]  ' }
                              else { '[FAIL]' }
                    $sync.Queue.Enqueue("$prefix $($r.Name)")
                }
            }
            catch {
                $sync.Queue.Enqueue("[FAIL] $($_.Exception.Message)")
            }
            $sync.Completed = $sync.Completed + 1
        }
        $sync.Done = $true
    })
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $line = $null
        while ($sync.Queue.TryDequeue([ref]$line)) {
            $LogBox.AppendText("$line`r`n")
            $LogBox.ScrollToEnd()
        }
        $Progress.Value = $sync.Completed
        if ($sync.Done) {
            $timer.Stop()
            try { $ps.EndInvoke($handle) | Out-Null } catch { $LogBox.AppendText("[FAIL] $($_.Exception.Message)`r`n") }
            $ps.Dispose()
            $rs.Close()
            $rs.Dispose()
            Set-UiBusy $false
            Update-StatusDisplay
            $StatusFooter.Text = if ($whatIf) { 'Dry run complete - nothing was changed.' } else { 'Apply complete. Restart to fully apply changes.' }
        }
    }.GetNewClosure())
    $timer.Start()
}

$window.FindName('BtnSelectAll').Add_Click({ foreach ($c in $Controls.Values) { $c.CheckBox.IsChecked = $true } })
$window.FindName('BtnSelectNone').Add_Click({ foreach ($c in $Controls.Values) { $c.CheckBox.IsChecked = $false } })
$window.FindName('BtnRecommended').Add_Click({
    foreach ($id in @($Controls.Keys)) { $Controls[$id].CheckBox.IsChecked = ($id -in $RecommendedIds) }
})
$window.FindName('BtnRefreshStatus').Add_Click({ Update-StatusDisplay; $StatusFooter.Text = 'Status refreshed.' })
$window.FindName('BtnRestorePoint').Add_Click({
    Set-UiBusy $true
    $LogBox.Clear()
    $StatusFooter.Text = 'Creating restore point (this can take a minute)...'
    New-OptimizerRestorePoint | ForEach-Object {
        $prefix = if ($_.Success) { '[OK]  ' } else { '[FAIL]' }
        $LogBox.AppendText("$prefix $($_.Name)`r`n")
    }
    $StatusFooter.Text = 'Restore point step finished.'
    Set-UiBusy $false
})
$window.FindName('BtnSystemRestore').Add_Click({
    $answer = [System.Windows.MessageBox]::Show('Launch Windows System Restore now?', 'System Restore', 'YesNo', 'Question')
    if ($answer -eq 'Yes') { Show-SystemRestore }
})
$window.FindName('BtnApply').Add_Click({ Start-ApplyJob -ids (Get-SelectedIds) -whatIf $false })
$window.FindName('BtnDryRun').Add_Click({ Start-ApplyJob -ids (Get-SelectedIds) -whatIf $true })
$window.FindName('BtnUndo').Add_Click({
    if (-not $ComboUndo.SelectedItem) { $StatusFooter.Text = 'Pick a category to undo first.'; return }
    $cat = [string]$ComboUndo.SelectedItem
    Set-UiBusy $true
    $LogBox.Clear()
    Undo-OptimizationCategory -Category $cat | ForEach-Object {
        $prefix = if ($_.Success) { '[OK]  ' } else { '[FAIL]' }
        $LogBox.AppendText("$prefix $($_.Name)`r`n")
    }
    Set-UiBusy $false
    Update-StatusDisplay
    $StatusFooter.Text = "Undo of '$cat' finished."
})

[void]$window.ShowDialog()
Write-OptimizerLog 'User closed GUI' | Out-Null
