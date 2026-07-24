$ErrorActionPreference = "Stop"

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}

if (-not $python) {
    throw "Python was not found."
}

if ($python.Name -eq "py.exe" -or $python.Name -eq "py") {
    & $python.Source -3 "$PSScriptRoot\apply_session_restore_fix_v2.py"
}
else {
    & $python.Source "$PSScriptRoot\apply_session_restore_fix_v2.py"
}

if ($LASTEXITCODE -ne 0) {
    throw "The robust session restore patch failed."
}
