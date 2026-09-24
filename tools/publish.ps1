# Publishes an update that players get automatically the next time they start the game.
#
#   powershell -File tools\publish.ps1 0.5.1 "What changed"
#
# 1. Writes the version into version.txt.
# 2. Exports the game data only (build/game.pck) - no .exe, players keep theirs.
# 3. Commits, tags and creates a GitHub release with game.pck attached.
#
# Needs: Godot export templates, the GitHub CLI (gh) logged in, and the repo set as
# REPO in scripts/boot/boot.gd. The base build players first install must already
# contain that REPO value (tools\build_base.ps1).

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Notes = "Update $Version"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = $env:GODOT
if (-not $Godot) { $Godot = "C:\Users\MagnusBradley\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }

$Gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $Gh) { $Gh = "$env:LOCALAPPDATA\gh-cli\bin\gh.exe" }

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3" }
Set-Location $Root
[IO.File]::WriteAllText("$Root\version.txt", "$Version`n")

New-Item -ItemType Directory -Force "$Root\build" | Out-Null
$pck = "$Root\build\game.pck"
if (Test-Path $pck) { Remove-Item $pck }
& $Godot --headless --path $Root --export-pack "Windows Desktop" $pck
if (-not (Test-Path $pck)) { throw "Export failed: build\game.pck was not created" }
Write-Host ("Exported game.pck ({0:N1} MB)" -f ((Get-Item $pck).Length / 1MB))

git add -A
git commit -m "Release v$Version" | Out-Null
git tag "v$Version"
git push --follow-tags
& $Gh release create "v$Version" $pck --title "v$Version" --notes $Notes
Write-Host "Published v$Version - players get it on their next launch."
