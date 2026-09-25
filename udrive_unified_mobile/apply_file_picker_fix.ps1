$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot "udrive_unified_mobile\lib"

if (-not (Test-Path $root)) {
    throw "udrive_unified_mobile\lib was not found. Extract/run this patch from the repository root."
}

$files = Get-ChildItem -Path $root -Recurse -Filter "*.dart"
$changed = 0

foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $updated = $content.Replace(
        "FilePicker.platform.pickFiles(",
        "FilePicker.pickFiles("
    )

    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText(
            $file.FullName,
            $updated,
            [System.Text.UTF8Encoding]::new($false)
        )
        Write-Host "Updated: $($file.FullName)"
        $changed++
    }
}

Write-Host ""
Write-Host "Completed. Dart files changed: $changed"

if ($changed -eq 0) {
    Write-Host "No old FilePicker.platform.pickFiles calls were found."
}
