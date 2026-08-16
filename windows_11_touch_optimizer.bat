@echo off
:: ---------------------------------------------------------------------------
:: Windows 11 Touchscreen Device Optimiser - console launcher
:: Thin bootstrap only: all elevation, menu, and tweak logic now live in
:: TouchOptimizer.ps1 / TouchOptimizer.psm1. Elevation happens exactly once
:: (Assert-Elevation in the module), which avoids the old double UAC-prompt
:: bug that came from checking admin status twice across the batch relaunch.
:: ---------------------------------------------------------------------------
setlocal
set "SCRIPT_DIR=%~dp0"
title Windows 11 Touchscreen Device Optimiser - by Matt Hurley

if not exist "%SCRIPT_DIR%TouchOptimizer.ps1" (
    echo [!] TouchOptimizer.ps1 not found next to this batch file.
    echo     Make sure the whole repository folder was copied, not just this .bat.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%TouchOptimizer.ps1"
exit /b %errorlevel%
