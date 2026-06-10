# Fail fast if Sherpa prebuilts missing (run before hvigor / DevEco build).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Arm = Join-Path $Root 'entry\libs\arm64-v8a\libsherpa-onnx-c-api.so'
if (-not (Test-Path $Arm)) {
    Write-Host 'ERROR: Sherpa libs missing. Run:' -ForegroundColor Red
    Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\setup_sherpa_ohos.ps1' -ForegroundColor Yellow
    exit 1
}
exit 0
