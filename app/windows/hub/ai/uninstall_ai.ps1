# Removes the LiveNow AI helpers: the "LiveNow AI" scheduled task and the OCR service folder
# (%LOCALAPPDATA%\LiveNowHub\ai, including its Python environment). Ollama and its downloaded models
# are left alone on purpose (`ollama rm <model>` removes a model). The hub and its data are not touched.
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}
$task = 'LiveNow AI'
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name like 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*LiveNowHub\ai*ocr_service.py*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'LiveNowHub\ai') -ErrorAction SilentlyContinue
foreach ($v in 'OLLAMA_KEEP_ALIVE', 'OLLAMA_MAX_LOADED_MODELS', 'OLLAMA_NUM_PARALLEL') {
    [Environment]::SetEnvironmentVariable($v, $null, 'User')
}
Write-Host 'LiveNow AI removed (Ollama and its models were kept).'
Read-Host 'Press Enter to close'
