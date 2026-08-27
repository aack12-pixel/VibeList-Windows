@echo off
setlocal
start "Vibe List" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0VibeList.ps1"
exit /b
