@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "PCCleanup.ps1"
pause
