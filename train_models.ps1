param(
    [string]$InputDir = "data",
    [string]$ClassifierOutput = "models\step_classifier.json",
    [string]$StepLengthOutput = "models\step_length_model.json",
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$resolvedInputDir = Join-Path $projectRoot $InputDir
$resolvedClassifierOutput = Join-Path $projectRoot $ClassifierOutput
$resolvedStepLengthOutput = Join-Path $projectRoot $StepLengthOutput

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

Write-Host "Training step classifier..."
py tools\train_step_classifier.py --input-dir $resolvedInputDir --output $resolvedClassifierOutput
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Training step length model..."
py tools\train_step_length_model.py --input-dir $resolvedInputDir --output $resolvedStepLengthOutput
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
Write-Host "Training finished successfully."
Write-Host "Step classifier: $resolvedClassifierOutput"
Write-Host "Step length model: $resolvedStepLengthOutput"

./build_apk.ps1