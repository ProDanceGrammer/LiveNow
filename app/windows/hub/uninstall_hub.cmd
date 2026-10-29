@echo off
rem Double-click to remove the LiveNow sync hub (its data folder is kept).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_hub.ps1"
pause
