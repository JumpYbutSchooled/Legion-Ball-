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

# Add this update to the in-game changelog (the menu's UPDATES page and the what's-new
# message), newest first; publishing the same version again replaces its entry.
$Log = "$Root\changelog.json"
$Entries = @()
if (Test-Path $Log) {
    $Parsed = Get-Content $Log -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($E in $Parsed) { if ($E.version -ne $Version) { $Entries += $E } }
}
$Entries = @([pscustomobject]@{ version = $Version; date = (Get-Date -Format "yyyy-MM-dd"); notes = $Notes }) + $Entries
[IO.File]::WriteAllText($Log, (ConvertTo-Json -InputObject $Entries -Depth 3), (New-Object Text.UTF8Encoding($false)))

New-Item -ItemType Directory -Force "$Root\build" | Out-Null
$pck = "$Root\build\game.pck"
if (Test-Path $pck) { Remove-Item $pck }
& $Godot --headless --path $Root --export-pack "Windows Desktop" $pck
if (-not (Test-Path $pck)) { throw "Export failed: build\game.pck was not created" }
Write-Host ("Exported game.pck ({0:N1} MB)" -f ((Get-Item $pck).Length / 1MB))

# Git and gh print progress on stderr, which "Stop" mode treats as fatal; check exit
# codes instead.
$ErrorActionPreference = "Continue"
function Check($what) { if ($LASTEXITCODE -ne 0) { Write-Error "$what failed (exit $LASTEXITCODE)"; exit 1 } }

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git commit -q -m "Release v$Version"; Check "git commit"
}
git tag "v$Version"; Check "git tag"
git push -q origin HEAD "v$Version" 2>&1 | Out-Null; Check "git push"
& $Gh release create "v$Version" $pck --title "v$Version" --notes $Notes; Check "gh release create"
Write-Host "Published v$Version - players get it on their next launch."

# Patch notes to Discord, if a webhook is set up: the LEGION_DISCORD_WEBHOOK environment
# variable, or the URL alone in tools\discord_webhook.txt (git-ignored: it's a secret).
$Hook = $env:LEGION_DISCORD_WEBHOOK
$HookFile = "$PSScriptRoot\discord_webhook.txt"
if (-not $Hook -and (Test-Path $HookFile)) { $Hook = (Get-Content $HookFile -Raw).Trim() }
if ($Hook) {
    $Body = @{
        username = "Leigon Ball"
        embeds = @(@{
            title = "Update v$Version is out"
            description = $Notes
            url = "https://github.com/JumpYbutSchooled/Legion-Ball-/releases/tag/v$Version"
            color = 5892863
            footer = @{ text = "Restart the game to update." }
        })
    } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Uri $Hook -Method Post -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($Body)) | Out-Null
        Write-Host "Posted the patch notes to Discord."
    } catch {
        Write-Warning "Couldn't post to Discord: $_"
    }
}
