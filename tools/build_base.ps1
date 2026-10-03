# Builds the full game (Ballistic.exe + Ballistic.pck) and zips it for friends to
# install once. After that, updates come from tools\publish.ps1 automatically.
#
#   powershell -File tools\build_base.ps1
#
# Needs Godot 4.7.2 export templates installed.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = $env:GODOT
if (-not $Godot) { $Godot = "C:\My stuff\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }

$out = "$Root\build\base"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
# Not headless: the Shader Baker needs the GPU to pre-build the shaders (no freezes
# the first time players see each effect).
& $Godot --path $Root --export-release "Windows Desktop" "$out\Ballistic.exe"
if (-not (Test-Path "$out\Ballistic.exe")) { throw "Export failed: no Ballistic.exe" }

$version = (Get-Content "$Root\version.txt" -Raw).Trim()
$zip = "$Root\build\Ballistic-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$out\*" -DestinationPath $zip
Write-Host "Built $zip - send this to friends. Updates after this are automatic."
