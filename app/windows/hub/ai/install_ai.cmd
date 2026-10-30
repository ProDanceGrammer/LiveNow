@echo off
rem Double-click to install or update the LiveNow AI helpers (OCR service + text model; asks for administrator rights).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ai.ps1"
pause
