@echo off
:: ---------------------------------------------------------------------------
:: Windows 11 Touchscreen Device Optimiser - GUI launcher
:: Thin bootstrap for the WPF front-end (TouchOptimizerGUI.ps1). Same
:: single-shot elevation as the console launcher.
:: ---------------------------------------------------------------------------
setlocal
set "SCRIPT_DIR=%~dp0"
title Windows 11 Touchscreen Device Optimiser (GUI) - by Matt Hurley

if not exist "%SCRIPT_DIR%TouchOptimizerGUI.ps1" (
    echo [!] TouchOptimizerGUI.ps1 not found next to this batch file.
    echo     Make sure the whole repository folder was copied, not just this .bat.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%TouchOptimizerGUI.ps1"
exit /b %errorlevel%
