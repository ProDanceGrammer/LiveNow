@echo off
rem Double-click to install or update the LiveNow sync hub (asks for administrator rights).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_hub.ps1"
pause
