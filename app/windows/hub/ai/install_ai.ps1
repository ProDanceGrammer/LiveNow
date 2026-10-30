# Installs (or updates) the LiveNow AI helpers on this PC: the local OCR service and the text model.
#
# What this script does (safe to run again):
#   1. copies ocr_service.py + requirements.txt to %LOCALAPPDATA%\LiveNowHub\ai and builds a Python
#      virtual environment there (pip install -r requirements.txt: needs internet, once),
#   2. checks that Ollama (https://ollama.com/download) is installed and runs `ollama pull <model>`,
#   3. sets the user environment for Ollama to stay light on an 8 GB PC: the model is unloaded 1 minute
#      after use (OLLAMA_KEEP_ALIVE=1m), one model, one request at a time. Restart Ollama to apply,
#   4. registers the scheduled task "LiveNow AI" (starts the OCR service at your Windows login,
#      restarts on failure) and starts it.
# OCR and the model run one after the other (never together) to fit in memory; the hub app does that.
# Needs Python 3.9-3.12 on PATH (python.org). Needs administrator rights for the task: the script asks
# Windows for them once (a UAC prompt). Never touches the hub or the app data.
param(
    [string]$Model = 'qwen2.5:3b-instruct',
    [int]$Port = 47655
)
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'LiveNowHub\ai'
$task = 'LiveNow AI'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Asking Windows for administrator rights (scheduled task)...'
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Model', "`"$Model`"", '-Port', $Port)
    return
}

if (-not (Test-Path (Join-Path $source 'ocr_service.py'))) {
    throw "ocr_service.py not found next to this script ($source)."
}

# --- 1. OCR service + virtual environment ---------------------------------------------------------
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name like 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*LiveNowHub\ai*ocr_service.py*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $source 'ocr_service.py') $dest -Force
Copy-Item (Join-Path $source 'requirements.txt') $dest -Force

$py = Get-Command py -ErrorAction SilentlyContinue
$pyExe = Get-Command python -ErrorAction SilentlyContinue
$venv = Join-Path $dest 'venv'
if (-not (Test-Path (Join-Path $venv 'Scripts\python.exe'))) {
    if ($py) { & py -3 -m venv $venv }
    elseif ($pyExe) { & python -m venv $venv }
    else { throw 'Python 3 not found. Install it from python.org (tick "Add to PATH"), then run this again.' }
    if ($LASTEXITCODE -ne 0) { throw 'Creating the Python environment failed.' }
}
$venvPy = Join-Path $venv 'Scripts\python.exe'
& $venvPy -m pip install --upgrade pip
& $venvPy -m pip install -r (Join-Path $dest 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install failed (see the messages above).' }

# --- 2. Ollama + the text model -------------------------------------------------------------------
$ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollama) {
    $guess = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    if (Test-Path $guess) { $ollama = $guess }
}
if (-not $ollama) {
    Write-Warning 'Ollama is not installed. Install it from https://ollama.com/download, then run this script again.'
} else {
    Write-Host "Pulling model $Model (first time: about 2 GB)..."
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) { Write-Warning "ollama pull $Model failed: check the model name and the internet connection." }
}

# --- 3. Keep memory low ----------------------------------------------------------------------------
[Environment]::SetEnvironmentVariable('OLLAMA_KEEP_ALIVE', '1m', 'User')
[Environment]::SetEnvironmentVariable('OLLAMA_MAX_LOADED_MODELS', '1', 'User')
[Environment]::SetEnvironmentVariable('OLLAMA_NUM_PARALLEL', '1', 'User')

# --- 4. Scheduled task ----------------------------------------------------------------------------
$pyw = Join-Path $venv 'Scripts\pythonw.exe'
$log = Join-Path $dest 'ocr.log'
$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute $pyw -WorkingDirectory $dest `
    -Argument "`"$(Join-Path $dest 'ocr_service.py')`" --port $Port --log `"$log`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'LiveNow AI: local OCR service for receipts (127.0.0.1 only)' -Force | Out-Null
Start-ScheduledTask -TaskName $task

Write-Host ''
Write-Host 'LiveNow AI installed and started.'
Write-Host "  OCR service : http://127.0.0.1:$Port/health  (log: $log)"
Write-Host "  text model  : $Model (Ollama, http://127.0.0.1:11434)"
Write-Host '  next        : restart Ollama once (tray icon > Quit, start it again) so the memory settings apply.'
Read-Host 'Press Enter to close'
