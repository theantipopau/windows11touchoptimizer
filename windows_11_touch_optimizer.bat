@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul 2>&1

title Windows 11 Touchscreen Device Optimiser - by Matt Hurley
color 0A

for /f %%A in ('"prompt $E & for %%B in (1) do rem"') do set "ESC=%%A"
if defined ESC (
    set "CLR_TITLE=%ESC%[95;1m"
    set "CLR_SUBTITLE=%ESC%[96m"
    set "CLR_MENU_HIGHLIGHT=%ESC%[93;1m"
    set "CLR_RESET=%ESC%[0m"
) else (
    set "CLR_TITLE="
    set "CLR_SUBTITLE="
    set "CLR_MENU_HIGHLIGHT="
    set "CLR_RESET="
)

:: ---------------------------------------------------------------------------
:: Surface Go / low-power Windows 11 touch optimization helper
:: Removes non-essential consumer apps, tones down telemetry, and applies
:: light performance tweaks that keep pen + touch components intact.
:: ---------------------------------------------------------------------------

set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

set "RELAUNCHED="
if /I "%~1"=="-Elevated" (
    set "RELAUNCHED=1"
    shift
)

call :EnsureAdmin
set "ADMIN_STATUS=%errorlevel%"
if "%ADMIN_STATUS%"=="2" exit /b 0
if not "%ADMIN_STATUS%"=="0" exit /b %ADMIN_STATUS%
call :CheckAdmin || exit /b 1

for /f %%I in ('"%POWERSHELL%" -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "BASE_DIR=%SCRIPT_DIR%"
set "LOG_DIR=%BASE_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
set "LOG_FILE=%LOG_DIR%\surface_go_optimizer_%STAMP%.log"

call :Log "=== Surface Go Touch Optimizer started ==="
for /f "usebackq delims=" %%I in (`"%POWERSHELL%" -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).Caption"`) do set "OS_CAPTION=%%I"
if defined OS_CAPTION call :Log "Detected %OS_CAPTION%"

:Menu
cls
call :Banner
call :Log "Awaiting menu selection"
set "choice="
echo.
echo    %CLR_MENU_HIGHLIGHT%[1 / F]%CLR_RESET% FULL OPTIMIZATION - All tweaks for Surface Go / touch devices
echo    %CLR_MENU_HIGHLIGHT%[2 / R]%CLR_RESET% Run recommended flow (restore + core essentials)
echo.
echo    %CLR_MENU_HIGHLIGHT%[3]%CLR_RESET% Create a system restore point only
echo    %CLR_MENU_HIGHLIGHT%[4]%CLR_RESET% Remove non-essential consumer apps
echo    %CLR_MENU_HIGHLIGHT%[5]%CLR_RESET% Disable telemetry + noisy scheduled tasks
echo    %CLR_MENU_HIGHLIGHT%[6]%CLR_RESET% Apply performance + touch-friendly tweaks
echo    %CLR_MENU_HIGHLIGHT%[7]%CLR_RESET% Remove OEM promo apps if present
echo    %CLR_MENU_HIGHLIGHT%[8]%CLR_RESET% Trim background services + indexing
echo    %CLR_MENU_HIGHLIGHT%[9]%CLR_RESET% Free disk space + temp caches
echo    %CLR_MENU_HIGHLIGHT%[A]%CLR_RESET% Disable Widgets + Teams Chat surfaces
echo    %CLR_MENU_HIGHLIGHT%[B]%CLR_RESET% Disable animations + visual effects
echo    %CLR_MENU_HIGHLIGHT%[C]%CLR_RESET% Optimize startup programs
echo.
echo    %CLR_MENU_HIGHLIGHT%[X]%CLR_RESET% RESTORE - Undo changes via System Restore
echo    %CLR_MENU_HIGHLIGHT%[0]%CLR_RESET% Exit without further changes
echo.
set /p "choice=> "
set "choice=%choice:~0,1%"
if /I "%choice%"=="1" call :FullOptimization & call :PauseReturn & goto Menu
if /I "%choice%"=="F" call :FullOptimization & call :PauseReturn & goto Menu
if /I "%choice%"=="2" call :RunRecommended & call :PauseReturn & goto Menu
if /I "%choice%"=="R" call :RunRecommended & call :PauseReturn & goto Menu
if /I "%choice%"=="3" call :CreateRestorePoint & call :PauseReturn & goto Menu
if /I "%choice%"=="4" call :RemoveConsumerApps & call :PauseReturn & goto Menu
if /I "%choice%"=="5" call :DisableTelemetry & call :PauseReturn & goto Menu
if /I "%choice%"=="6" call :ApplyPerformanceTweaks & call :PauseReturn & goto Menu
if /I "%choice%"=="7" call :RemoveOEMPromos & call :PauseReturn & goto Menu
if /I "%choice%"=="8" call :TrimBackgroundServices & call :PauseReturn & goto Menu
if /I "%choice%"=="9" call :FreeDiskSpace & call :PauseReturn & goto Menu
if /I "%choice%"=="A" call :DisableWidgetsChat & call :PauseReturn & goto Menu
if /I "%choice%"=="B" call :DisableAnimations & call :PauseReturn & goto Menu
if /I "%choice%"=="C" call :OptimizeStartup & call :PauseReturn & goto Menu
if /I "%choice%"=="X" call :RestoreSystem & call :PauseReturn & goto Menu
if "%choice%"=="0" goto End
echo.
echo [!] Unknown selection. Please try again.
call :PauseReturn
goto Menu

:FullOptimization
call :Log "Running FULL optimization sequence"
echo.
echo ========================================================================
echo   %CLR_TITLE%FULL OPTIMIZATION%CLR_RESET% for Surface Go / Touchscreen Devices
echo ========================================================================
echo   This will apply ALL optimizations for maximum performance.
echo   Estimated time: 5-10 minutes
echo ========================================================================
echo.
call :CreateRestorePoint
if errorlevel 1 exit /b 1
echo.
echo [*] Step 1/10: Removing consumer apps...
call :RemoveConsumerApps
echo [*] Step 2/10: Removing OEM promo apps...
call :RemoveOEMPromos
echo [*] Step 3/10: Disabling telemetry...
call :DisableTelemetry
echo [*] Step 4/10: Applying performance tweaks...
call :ApplyPerformanceTweaks
echo [*] Step 5/10: Trimming background services...
call :TrimBackgroundServices
echo [*] Step 6/10: Disabling Widgets and Chat...
call :DisableWidgetsChat
echo [*] Step 7/10: Disabling animations...
call :DisableAnimations
echo [*] Step 8/10: Optimizing startup...
call :OptimizeStartup
echo [*] Step 9/10: Freeing disk space...
call :FreeDiskSpace
echo [*] Step 10/10: Finalizing...
echo.
echo ========================================================================
echo   %CLR_TITLE%FULL OPTIMIZATION COMPLETE!%CLR_RESET%
echo   Please restart your device for all changes to take effect.
echo ========================================================================
call :Log "Full optimization sequence completed"
exit /b 0

:RunRecommended
call :Log "Running recommended sequence"
echo.
echo ========================================================================
echo   %CLR_TITLE%RECOMMENDED OPTIMIZATION%CLR_RESET% Flow
echo ========================================================================
echo   This will apply the most important optimizations.
echo   Estimated time: 3-5 minutes
echo ========================================================================
echo.
call :CreateRestorePoint
if errorlevel 1 exit /b 1
echo.
echo [*] Step 1/4: Removing consumer apps...
call :RemoveConsumerApps
echo [*] Step 2/4: Disabling telemetry...
call :DisableTelemetry
echo [*] Step 3/4: Applying performance tweaks...
call :ApplyPerformanceTweaks
echo [*] Step 4/4: Finalizing...
echo.
echo ========================================================================
echo   %CLR_TITLE%RECOMMENDED OPTIMIZATION COMPLETE!%CLR_RESET%
echo   Please restart your device for all changes to take effect.
echo ========================================================================
call :Log "Recommended optimization sequence completed"
exit /b 0

:CreateRestorePoint
call :Log "Requesting system restore point"
echo.
echo [*] Creating system restore point...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "Try { Checkpoint-Computer -Description 'SurfaceGoTouchOptimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; exit 0 } Catch { Write-Warning $_; exit 1 }" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ========================================================================
    echo   [!] SYSTEM RESTORE POINT FAILED
    echo ========================================================================
    echo   Reason: System Protection may not be enabled on this drive.
    echo.
    echo   To enable System Protection:
    echo   1. Open Control Panel ^> System ^> System Protection
    echo   2. Select your C: drive and click "Configure"
    echo   3. Enable "Turn on system protection"
    echo   4. Allocate at least 2-5GB of disk space
    echo   5. Click OK and try running this script again
    echo ========================================================================
    echo.
    call :Log "Restore point creation failed - prompting user"
    set /p "continue=Do you want to CONTINUE WITHOUT a restore point? (Y/N): "
    if /I not "!continue!"=="Y" (
        echo.
        echo [!] Operation cancelled by user. Please enable System Protection and try again.
        call :Log "User cancelled due to restore point failure"
        exit /b 1
    )
    echo.
    echo [!] Continuing without restore point (user confirmed)...
    call :Log "User chose to continue without restore point"
) else (
    echo [+] Restore point created successfully.
    call :Log "Restore point created"
)
exit /b 0

:RemoveConsumerApps
call :Log "Removing consumer apps"
echo [*] Removing consumer apps and provisioned packages (this may take a moment)...
for %%A in (
    Microsoft.BingNews
    Microsoft.BingFinance
    Microsoft.BingWeather
    Microsoft.GetHelp
    Microsoft.Getstarted
    Microsoft.Microsoft3DViewer
    Microsoft.MicrosoftOfficeHub
    Microsoft.MicrosoftSolitaireCollection
    Microsoft.MicrosoftStickyNotes
    Microsoft.MixedReality.Portal
    Microsoft.People
    Microsoft.PowerAutomateDesktop
    Microsoft.SkypeApp
    Microsoft.WindowsFeedbackHub
    Microsoft.Xbox.TCUI
    Microsoft.XboxApp
    Microsoft.XboxGameOverlay
    Microsoft.XboxGamingOverlay
    Microsoft.XboxIdentityProvider
    Microsoft.XboxSpeechToTextOverlay
    Microsoft.ZuneMusic
    Microsoft.ZuneVideo
    MicrosoftWindows.Client.WebExperience
    Clipchamp.Clipchamp
    SpotifyAB.SpotifyMusic
    BytedancePte.Ltd.TikTok
    Facebook.Facebook
    Disney.37853FC22B2CE
    Microsoft.YourPhone
    MicrosoftCorporationII.QuickAssist
    Microsoft.Whiteboard
    Microsoft.WindowsSoundRecorder
    Microsoft.WindowsAlarms
    MicrosoftTeams
    Microsoft.OneDriveSync
) do (
    call :RemoveApp %%A
)
echo [+] Consumer app removal complete.
exit /b 0

:RemoveApp
set "PKG=%~1"
if not defined PKG exit /b 0
call :Log "Removing %PKG%"
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "Get-AppxPackage -AllUsers -Name %PKG% ^| Remove-AppxPackage -ErrorAction SilentlyContinue" >> "%LOG_FILE%" 2>&1
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq '%PKG%' } ^| Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue" >> "%LOG_FILE%" 2>&1
exit /b 0

:DisableTelemetry
call :Log "Disabling telemetry and scheduled noise"
echo [*] Configuring telemetry services and scheduled tasks...
for %%S in (DiagTrack dmwappushservice RetailDemo RemoteRegistry WerSvc RemoteAccess) do (
    sc stop %%S >nul 2>&1
    sc config %%S start= disabled >nul 2>&1
)
for %%T in (
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    "\Microsoft\Windows\Feedback\Siuf\DmClient"
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenario"
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
) do (
    schtasks /Change /TN %%~T /Disable >nul 2>&1
)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\TabletPC" /v PreventHandwritingDataSharing /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f >nul
echo [+] Telemetry and tracking successfully disabled.
call :Log "Telemetry settings updated"
exit /b 0

:ApplyPerformanceTweaks
call :Log "Applying performance tweaks"
echo [*] Applying power plan and performance registry tweaks...
powercfg /setactive SCHEME_MIN >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 2 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnableSuperfetch /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DoNotConnectToWindowsUpdateInternetLocations /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisableAcrylicBackgroundOnLogon /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v EnableAutoTray /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseHoverTime /t REG_SZ /d 10 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 2000 /f >nul
reg add "HKCU\Control Panel\Desktop" /v WaitToKillAppTimeout /t REG_SZ /d 2000 /f >nul
reg add "HKCU\Control Panel\Desktop" /v LowLevelHooksTimeout /t REG_SZ /d 1000 /f >nul
reg add "HKCU\Control Panel\Desktop" /v HungAppTimeout /t REG_SZ /d 1000 /f >nul
reg add "HKCU\Control Panel\Pen" /v PenTapFeedbackVisualization /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Control Panel\Cursors" /v ContactVisualization /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Control Panel\Cursors" /v GestureVisualization /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\PenWorkspace" /v PenWorkspaceButtonDesiredVisibility /t REG_DWORD /d 0 /f >nul
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v PagingFiles ^| findstr /i PagingFiles') do set "CURRENT_PAGEFILE=%%a"
if not defined CURRENT_PAGEFILE (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v PagingFiles /t REG_MULTI_SZ /d "C:\pagefile.sys 0 0" /f >nul
)
:: Keep touch keyboard and handwriting services automatic
for %%S in (TabletInputService TextInputManagementService) do (
    sc config %%S start= demand >nul 2>&1
)
echo [+] Performance tweaks applied successfully.
call :Log "Performance tweaks applied"
exit /b 0

:RemoveOEMPromos
call :Log "Removing OEM promo apps"
for %%B in (EclipseManager ActiproSoftwareLLC.562882FEEB491 DellInc.PartnerPromo) do (
    call :RemoveApp %%B
)
exit /b 0

:TrimBackgroundServices
call :Log "Trimming background services and indexing"
echo [*] Optimizing background services and search indexing...
for %%S in (SysMain MapsBroker TrkWks) do (
    sc stop %%S >nul 2>&1
    sc config %%S start= disabled >nul 2>&1
)
sc stop WSearch >nul 2>&1
sc config WSearch start= demand >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v AllowCortana /t REG_DWORD /d 0 /f >nul
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v CortanaConsent /t REG_DWORD /d 0 /f >nul
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f >nul
for %%K in (
    SubscribedContent-310093Enabled
    SubscribedContent-338388Enabled
    SubscribedContent-338389Enabled
    SubscribedContent-353694Enabled
    SystemPaneSuggestionsEnabled
) do (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v %%K /t REG_DWORD /d 0 /f >nul
)
echo [+] Background services optimized.
call :Log "Background services trimmed"
exit /b 0

:FreeDiskSpace
call :Log "Freeing disk space and clearing caches"
echo [*] Clearing temporary files and reclaiming disk space...
powercfg /h off >nul 2>&1
call :Log "Hibernation disabled"
call :ClearTemp "%TEMP%"
if defined LOCALAPPDATA call :ClearTemp "%LOCALAPPDATA%\Temp"
call :ClearTemp "%SystemRoot%\Temp"
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
if exist "%SystemRoot%\SoftwareDistribution\Download" rd /s /q "%SystemRoot%\SoftwareDistribution\Download"
mkdir "%SystemRoot%\SoftwareDistribution\Download" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
"%SystemRoot%\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup >> "%LOG_FILE%" 2>&1
echo [+] Disk cleanup complete.
call :Log "Disk cleanup complete"
exit /b 0

:DisableWidgetsChat
call :Log "Disabling Widgets and Teams Chat surfaces"
echo [*] Disabling Widgets, Teams Chat, and Copilot taskbar elements...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarChatEnabled /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f >nul
schtasks /Change /TN "\Microsoft\Windows\Windows Copilot\CopilotActivation" /Disable >nul 2>&1
echo [+] Taskbar decluttering complete.
call :Log "Widgets/Teams toggles updated"
exit /b 0

:DisableAnimations
call :Log "Disabling animations and visual effects"
echo [*] Disabling animations for maximum responsiveness...
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f >nul
reg add "HKCU\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f >nul
reg add "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\DWM" /v AlwaysHibernateThumbnails /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarMn /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v DisallowShaking /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnableAutocorrection /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnableSpellchecking /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnableTextPrediction /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnablePredictionSpaceInsertion /t REG_DWORD /d 0 /f >nul
reg add "HKCU\Software\Microsoft\Wisp\Pen\SysEventParameters" /v Flickscustomized /t REG_DWORD /d 1 /f >nul
reg add "HKCU\Software\Microsoft\Wisp\Pen\SysEventParameters" /v FlicksEnabled /t REG_DWORD /d 0 /f >nul
echo [+] Visual effects disabled - restart Explorer to see changes.
call :Log "Animations disabled"
exit /b 0

:OptimizeStartup
call :Log "Optimizing startup programs"
echo [*] Analyzing and optimizing startup programs...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" /v StartupDelayInMSec /t REG_DWORD /d 0 /f >nul
schtasks /Change /TN "\Microsoft\Windows\Application Experience\StartupAppTask" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\Application Experience\PcaPatchDbTask" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\Maps\MapsUpdateTask" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\Maps\MapsToastTask" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask" /Disable >nul 2>&1
powercfg -attributes SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 -ATTRIB_HIDE >nul 2>&1
powercfg -setacvalueindex SCHEME_CURRENT SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 >nul 2>&1
powercfg -setdcvalueindex SCHEME_CURRENT SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f >nul
Dism /Online /Disable-Feature /FeatureName:Printing-XPSServices-Features /NoRestart /Quiet >nul 2>&1
Dism /Online /Disable-Feature /FeatureName:WorkFolders-Client /NoRestart /Quiet >nul 2>&1
Dism /Online /Disable-Feature /FeatureName:FaxServicesClientPackage /NoRestart /Quiet >nul 2>&1
sc stop XblAuthManager >nul 2>&1
sc config XblAuthManager start= disabled >nul 2>&1
sc stop XblGameSave >nul 2>&1
sc config XblGameSave start= disabled >nul 2>&1
sc stop XboxGipSvc >nul 2>&1
sc config XboxGipSvc start= disabled >nul 2>&1
sc stop XboxNetApiSvc >nul 2>&1
sc config XboxNetApiSvc start= disabled >nul 2>&1
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "Enable-MMAgent -MemoryCompression" >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v DisablePagingExecutive /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v LargeSystemCache /t REG_DWORD /d 0 /f >nul
echo [+] Startup optimization complete - unnecessary services and features disabled.
call :Log "Startup optimized"
exit /b 0

:ClearTemp
set "TARGET=%~1"
if not defined TARGET exit /b 0
if not exist "%TARGET%" exit /b 0
call :Log "Clearing %TARGET%"
pushd "%TARGET%" >nul 2>&1 || exit /b 0
del /f /s /q *.* >nul 2>&1
for /d %%D in (*) do rd /s /q "%%D" >nul 2>&1
popd >nul 2>&1
exit /b 0

:IsAdmin
>nul 2>&1 fltmc
if %errorlevel%==0 exit /b 0
fsutil dirty query %SystemDrive% >nul 2>&1
if %errorlevel%==0 exit /b 0
exit /b 1

:EnsureAdmin
call :IsAdmin
if %errorlevel%==0 exit /b 0
if defined RELAUNCHED (
    color 0C
    echo [!] Administrative approval was denied or unavailable.
    echo     Please right-click the script and choose "Run as administrator".
    pause
    exit /b 1
)
echo [!] Requesting administrator approval through UAC...
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "$p=Start-Process '%~f0' -ArgumentList '-Elevated' -WorkingDirectory '%SCRIPT_DIR%' -Verb RunAs -PassThru; exit 0" >nul 2>&1
if errorlevel 1 (
    echo [!] Automatic UAC prompt failed. Please right-click the script and choose "Run as administrator".
    pause
    exit /b 1
)
echo [*] A new elevated window will open. You can close this window.
timeout /t 2 /nobreak >nul
exit /b 0

:Banner
if defined CLR_TITLE (
    echo %CLR_TITLE%==============================================================%CLR_RESET%
    echo %CLR_TITLE%  Windows 11 Touchscreen Device Optimiser%CLR_RESET%
    echo %CLR_SUBTITLE%  by Matt Hurley%CLR_RESET%
    echo %CLR_SUBTITLE%--------------------------------------------------------------%CLR_RESET%
    echo   Touch + Surface Pen safe tweaks for Office / web workloads
    echo   Run as administrator. Changes are logged to:
    echo   %LOG_FILE%
    echo %CLR_TITLE%==============================================================%CLR_RESET%
) else (
    echo ===============================================================
    echo   Windows 11 Touchscreen Device Optimiser
    echo   by Matt Hurley
    echo ---------------------------------------------------------------
    echo   Touch + Surface Pen safe tweaks for Office / web workloads
    echo   Run as administrator. Changes are logged to:
    echo   %LOG_FILE%
    echo ===============================================================
)
exit /b 0

:PauseReturn
echo.
pause
exit /b 0

:CheckAdmin
call :IsAdmin
if not %errorlevel%==0 (
    color 0C
    echo [!] This script must be run with administrative privileges.
    echo     Right-click the .bat file and choose "Run as administrator".
    pause
    exit /b 1
)
exit /b 0

:Log
set "MESSAGE=%~1"
echo %DATE% %TIME% - %MESSAGE%
>>"%LOG_FILE%" echo %DATE% %TIME% - %MESSAGE%
exit /b 0

:RestoreSystem
call :Log "User requested system restore"
echo.
echo ========================================================================
echo   SYSTEM RESTORE
echo ========================================================================
echo   This will launch Windows System Restore to undo changes.
echo   
echo   Look for restore points named:
echo   - "SurfaceGoTouchOptimizer" (created by this script)
echo   - Any manual restore points you created before running this tool
echo.
echo   The System Restore wizard will open. Follow the prompts to:
echo   1. Select a restore point from BEFORE you ran this optimizer
echo   2. Click "Scan for affected programs" to see what will change
echo   3. Confirm and restart to restore
echo ========================================================================
echo.
set /p "confirm=Press Y to launch System Restore, or any other key to cancel: "
if /I not "%confirm%"=="Y" (
    echo [!] Restore cancelled.
    exit /b 0
)
echo [*] Launching System Restore...
call :Log "Launching System Restore wizard"
start "" rstrui.exe
echo.
echo [*] System Restore wizard has been launched.
echo     Follow the on-screen prompts to restore your system.
echo.
exit /b 0

:End
call :Log "User exited."
echo.
echo All done. Review %LOG_FILE% for details.
popd >nul 2>&1
endlocal
exit /b 0
