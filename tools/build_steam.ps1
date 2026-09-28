# Builds the Steam version into build\steam\ (Ballistic.exe with the game packed inside,
# the Steam libraries next to it). Upload that folder as the Windows depot with SteamPipe.
# The Steam build has the "steam" feature: no GitHub auto-updater, no GitHub patches.
#
#   powershell -File tools\build_steam.ps1            (release build)
#   powershell -File tools\build_steam.ps1 -Test      (adds steam_appid.txt for testing)
#
# Before uploading: set APP_ID in scripts\steam.gd to your real App ID, and make the
# achievements listed there (same API names) in the Steamworks partner site.

param([switch]$Test)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = $env:GODOT
if (-not $Godot) { $Godot = "C:\My stuff\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }

$out = Join-Path $Root "build\steam"
New-Item -ItemType Directory -Force $out | Out-Null
# Start clean: only this build's files in the depot folder.
Get-ChildItem $out -File | ForEach-Object { $_.Delete() }
& $Godot --headless --path $Root --export-release "Windows Steam" "$out\Ballistic.exe"
if (-not (Test-Path "$out\Ballistic.exe")) { throw "Export failed: no Ballistic.exe" }
if (-not (Test-Path "$out\steam_api64.dll")) {
    Copy-Item "$Root\addons\godotsteam\win64\steam_api64.dll" $out
}
# Godot's and GodotSteam's licenses have to ship with the game.
& $Godot --headless --path $Root --script tools/make_licenses.gd -- "$out\THIRD_PARTY_LICENSES.txt"
if (-not (Test-Path "$out\THIRD_PARTY_LICENSES.txt")) { throw "Couldn't write THIRD_PARTY_LICENSES.txt" }
$appId = (Select-String "$Root\scripts\steam.gd" -Pattern 'const APP_ID := (\d+)').Matches[0].Groups[1].Value
if ($Test) {
    # Lets the game start Steam when run from this folder (not needed once Steam installs it).
    Set-Content "$out\steam_appid.txt" $appId -NoNewline
}
Write-Host "Steam build ready in $out (App ID $appId)."
