# Removes the LiveNow sync hub's program copy, scheduled task and firewall rule.
# Its DATA (%APPDATA%\io.livenow\livenow\hub: database, log, backups) is left alone on purpose;
# delete that folder yourself only when you are sure no device needs it.
$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}
$task = 'LiveNow Hub'
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Get-Process livenow -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$env:LOCALAPPDATA\LiveNowHub\*" } |
    Stop-Process -Force
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName 'LiveNow hub 47653' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\LiveNowHub" -ErrorAction SilentlyContinue
Write-Host 'LiveNow hub removed (its data folder was kept).'
Read-Host 'Press Enter to close'
