@echo off
rem Double-click to remove the LiveNow AI helpers (asks for administrator rights).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_ai.ps1"
pause
