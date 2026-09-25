$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$payload = Join-Path $PSScriptRoot "patch_payload"

$required = @(
    "admin_portal\app\verification\page.tsx",
    "admin_portal\app\verification\verification.module.css",
    "admin_portal\app\lib\admin-api.ts"
)

foreach ($relative in $required) {
    $source = Join-Path $payload $relative
    $target = Join-Path $repoRoot $relative

    if (-not (Test-Path $source)) {
        throw "Patch file is missing: $source"
    }

    $targetFolder = Split-Path $target -Parent
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    Copy-Item $source $target -Force
    Write-Host "Updated $relative" -ForegroundColor Green
}

Write-Host ""
Write-Host "Patch applied successfully." -ForegroundColor Cyan
Write-Host "Open GitHub Desktop, commit these three files, then click Push origin."
