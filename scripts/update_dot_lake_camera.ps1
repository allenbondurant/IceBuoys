$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceFolder = "C:\Users\Allen\Documents\SpypointDownloads\68dd700d7c3ead48e01172e1"
$cameraFolder = "www/camera/dot-lake"
$manifest = "data/camera_manifest.csv"
$rawBaseUrl = "https://raw.githubusercontent.com/allenbondurant/IceBuoys/main/www/camera/dot-lake"

Set-Location $repoRoot

if (-not (Test-Path $sourceFolder)) {
    throw "SpyPoint source folder does not exist: $sourceFolder"
}

# The LI-COR GitHub Action may have committed new data since the previous run.
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) {
    throw "Could not update the local IceBuoys repository."
}

python scripts/sync_spypoint_folder.py `
    $sourceFolder `
    --site-id dot-lake `
    --keep 12 `
    --raw-base-url $rawBaseUrl
if ($LASTEXITCODE -ne 0) {
    throw "The camera synchronization script failed."
}

git add -A -- $manifest $cameraFolder
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No new Dot Lake camera images."
    exit 0
}

git commit -m "Update Dot Lake camera imagery"
if ($LASTEXITCODE -ne 0) {
    throw "Could not commit the camera update."
}

# Catch any LI-COR update that arrived while images were being prepared.
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) {
    throw "Could not integrate the latest remote data before pushing."
}

git push origin main
if ($LASTEXITCODE -ne 0) {
    throw "Could not push the camera update to GitHub."
}

Write-Host "Dot Lake camera imagery updated successfully."
