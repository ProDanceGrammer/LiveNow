# Packs the Windows release build into a portable zip: livenow.exe + its DLLs +
# the three Visual C++ runtime DLLs (app-local deployment, so it also starts on a
# PC that never installed the redistributable) + a short README + the hub
# install/uninstall/start scripts from app/windows/hub/.
#
#   flutter build windows --release
#   pwsh app/windows/package/pack_windows.ps1 [-Out <zip path>]
param(
  [string]$Release = (Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release'),
  [string]$Out = (Join-Path $PSScriptRoot '..\..\LiveNow-windows-x64.zip')
)
$ErrorActionPreference = 'Stop'

$Release = (Resolve-Path $Release).Path
if (-not (Test-Path (Join-Path $Release 'livenow.exe'))) {
  throw "livenow.exe not found in $Release - run 'flutter build windows --release' first."
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('livenow-pack-' + [guid]::NewGuid())
$root = Join-Path $stage 'LiveNow'
New-Item -ItemType Directory -Path $root | Out-Null
Copy-Item -Path (Join-Path $Release '*') -Destination $root -Recurse

foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
  $src = Join-Path $env:SystemRoot "System32\$dll"
  if (-not (Test-Path $src)) { throw "$dll not found in System32." }
  Copy-Item $src $root
}
Copy-Item (Join-Path $PSScriptRoot 'README.txt') $root
foreach ($f in 'install_hub.ps1', 'uninstall_hub.ps1', 'install_hub.cmd', 'uninstall_hub.cmd', 'start_hub.cmd') {
  Copy-Item (Join-Path $PSScriptRoot "..\hub\$f") $root
}

if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path $root -DestinationPath $Out
Remove-Item $stage -Recurse -Force
Write-Host ("Wrote {0} ({1:N1} MB)" -f (Resolve-Path $Out).Path, ((Get-Item $Out).Length / 1MB))
