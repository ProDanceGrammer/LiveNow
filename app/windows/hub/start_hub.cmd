@echo off
rem Runs the LiveNow sync hub once, from this folder, until you close this window or log off.
rem No installation, no administrator rights; use install_hub.cmd for an always-on hub.
cd /d "%~dp0"
echo LiveNow hub is running. Close this window to stop it.
livenow.exe --hub
pause
