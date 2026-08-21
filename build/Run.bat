@echo off
setlocal DisableDelayedExpansion
:: PC Cleanup v2 -- Launcher
:: Right-click > Run as Administrator
cd /d "%~dp0"
if not exist "pccleanup.ps1" goto :missing
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0pccleanup.ps1" %*
set "rc=%errorlevel%"
pause
exit /b %rc%

:missing
echo.
echo   [x] Could not find pccleanup.ps1 next to this launcher
echo       Why: The file is missing from this folder. Antivirus may have
echo            quarantined it, or the ZIP was not fully extracted.
echo       Fix: Re-extract pc-cleanup-v2.zip so that Run.bat, pccleanup.ps1
echo            and the config folder all sit together, then run it again.
echo.
pause
exit /b 1
