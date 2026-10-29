# Installs (or updates) the LiveNow sync hub on this PC from the unzipped LiveNow folder.
#
# The hub is the same LiveNow program started as `livenow.exe --hub`: no window, it only keeps the
# sync database and answers the desktop window and the iPhone, even when LiveNow itself is closed.
# What this script does (safe to run again; it is also the update script after you unzip a newer build):
#   1. copies the app (the folder this script sits in) to %LOCALAPPDATA%\LiveNowHub\app, so moving or
#      deleting the unzipped folder cannot break the hub,
#   2. registers the scheduled task "LiveNow Hub" (starts at your Windows login, restarts on failure),
#   3. opens TCP port 47653 for the home network and Tailscale (100.64.0.0/10) only,
#   4. starts the hub.
# Steps 1-3 need administrator rights: the script asks Windows for them once (a UAC prompt).
# The hub's data lives in %APPDATA%\io.livenow\livenow\hub (its own database, log and backups).
# Never touches the data of the desktop app.
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'LiveNowHub\app'
$task = 'LiveNow Hub'
$rule = 'LiveNow hub 47653'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Asking Windows for administrator rights (task + firewall)...'
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}

if (-not (Test-Path (Join-Path $source 'livenow.exe'))) {
    throw "livenow.exe not found next to this script ($source). Run it from the unzipped LiveNow folder."
}
if ($source.TrimEnd('\') -ieq $dest.TrimEnd('\')) {
    throw 'Run this script from the unzipped LiveNow folder, not from the installed copy.'
}

# Stop a running hub first (only the copy in LiveNowHub, never the desktop window).
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Get-Process livenow -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$env:LOCALAPPDATA\LiveNowHub\*" } |
    Stop-Process -Force
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $dest | Out-Null
robocopy $source $dest /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

$exe = Join-Path $dest 'livenow.exe'
$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute $exe -Argument '--hub' -WorkingDirectory $dest
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'LiveNow sync hub (hidden, keeps the sync database running)' -Force | Out-Null

Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Protocol TCP -LocalPort 47653 `
    -Profile Any -RemoteAddress 'LocalSubnet', '100.64.0.0/10' | Out-Null

Start-ScheduledTask -TaskName $task
Write-Host ''
Write-Host 'LiveNow hub installed and started.'
Write-Host "  program : $exe --hub"
Write-Host "  data    : $env:APPDATA\io.livenow\livenow\hub  (hub.log, backups, its database)"
Write-Host '  next    : in the LiveNow window open Sync > "Connect to the local hub".'
Read-Host 'Press Enter to close'
