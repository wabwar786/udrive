$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$mobileRoot = Join-Path $repoRoot "udrive_unified_mobile\lib"
$cssFile = Join-Path $repoRoot "admin_portal\app\verification\verification.module.css"

if (-not (Test-Path $mobileRoot)) {
    throw "Missing folder: udrive_unified_mobile\lib. Extract this ZIP into the repository root."
}

if (-not (Test-Path $cssFile)) {
    throw "Missing file: admin_portal\app\verification\verification.module.css. Extract this ZIP into the repository root."
}

$dartChanged = 0
Get-ChildItem -Path $mobileRoot -Recurse -Filter "*.dart" | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    $updated = $content.Replace(
        "FilePicker.platform.pickFiles(",
        "FilePicker.pickFiles("
    )

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText(
            $_.FullName,
            $updated,
            [System.Text.UTF8Encoding]::new($false)
        )
        Write-Host "Flutter fixed: $($_.FullName)"
        $dartChanged++
    }
}

$css = Get-Content -LiteralPath $cssFile -Raw
$updatedCss = $css.Replace(
    "}button{font:inherit}",
    "}.page button,.loginPage button{font:inherit}"
)

if ($updatedCss -eq $css) {
    $updatedCss = $css.Replace(
        "button{font:inherit}",
        ".page button,.loginPage button{font:inherit}"
    )
}

$cssChanged = $updatedCss -ne $css

if ($cssChanged) {
    [System.IO.File]::WriteAllText(
        $cssFile,
        $updatedCss,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Admin CSS fixed: $cssFile"
}

$remainingPickerCalls = Get-ChildItem -Path $mobileRoot -Recurse -Filter "*.dart" |
    Select-String -SimpleMatch "FilePicker.platform.pickFiles("

$remainingGlobalButton = Select-String -Path $cssFile -Pattern "(^|})button\{font:inherit\}" -AllMatches

Write-Host ""
Write-Host "Flutter files changed: $dartChanged"
Write-Host "Admin CSS changed: $cssChanged"

if ($remainingPickerCalls) {
    throw "Old FilePicker.platform.pickFiles calls still remain."
}

if ($remainingGlobalButton) {
    throw "The impure global button CSS selector still remains."
}

Write-Host "Validation passed. Both Railway build errors are fixed."
