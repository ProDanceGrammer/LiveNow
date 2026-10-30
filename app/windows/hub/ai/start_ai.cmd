@echo off
rem Runs the LiveNow OCR service once, from this folder, until you close this window.
rem Needs the packages from requirements.txt in the Python on PATH; install_ai.cmd sets up an always-on service instead.
cd /d "%~dp0"
echo LiveNow OCR service is running on 127.0.0.1:47655. Close this window to stop it.
python ocr_service.py --port 47655
pause
