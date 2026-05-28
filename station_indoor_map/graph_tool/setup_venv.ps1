$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$venvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3 -m venv .venv
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        python -m venv .venv
    } else {
        throw "Python launcher not found. Install Python or add python to PATH."
    }
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r requirements.txt

Write-Host ""
Write-Host "[OK] graph_tool venv is ready."
Write-Host "Activate it with:"
Write-Host "  .\.venv\Scripts\Activate.ps1"
