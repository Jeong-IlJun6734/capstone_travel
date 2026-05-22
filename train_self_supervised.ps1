param(
    [string]$InputDir = "data",
    [string]$Output = "models\self_supervised_step_model.json",
    [int]$Epochs = 3600,
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$resolvedInputDir = Join-Path $projectRoot $InputDir
$resolvedOutput = Join-Path $projectRoot $Output

if (-not (Test-Path $resolvedInputDir)) {
    Write-Error "Input directory not found: $resolvedInputDir"
    exit 1
}

$csvFiles = Get-ChildItem -Path $resolvedInputDir -Filter *.csv -File
if (-not $csvFiles) {
    Write-Error "No CSV files found in: $resolvedInputDir"
    exit 1
}

Write-Host "Found $($csvFiles.Count) CSV file(s) in $resolvedInputDir"
Write-Host "Training self-supervised step model..."
py tools\train_self_supervised_step_model.py --input-dir $resolvedInputDir --output $resolvedOutput --epochs $Epochs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if (-not $SkipAnalyze) {
    Write-Host "Running flutter analyze..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "Self-supervised model written to:"
Write-Host $resolvedOutput

./build_apk.ps1
