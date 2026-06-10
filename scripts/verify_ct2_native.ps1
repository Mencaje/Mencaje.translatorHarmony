# Verify arm64 CTranslate2 prebuilts exist before DevEco build (isCt2Linked=false on device = stub HAP).
# Usage: powershell -ExecutionPolicy Bypass -File scripts\verify_ct2_native.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Abi = 'arm64-v8a'
$LibDir = Join-Path $Root "entry\libs\$Abi"

$required = @(
    'libctranslate2.so',
    'libsentencepiece.a'
)
$missing = @()
foreach ($name in $required) {
    $p = Join-Path $LibDir $name
    if (-not (Test-Path $p)) { $missing += $name }
}

if ($missing.Count -gt 0) {
    Write-Host "[FAIL] Missing in entry\libs\$Abi :" ($missing -join ', ') -ForegroundColor Red
    Write-Host 'Run: powershell -File scripts\build_ctranslate2_ohos.ps1 -Abi arm64-v8a' -ForegroundColor Cyan
    Write-Host 'And: powershell -File scripts\build_sentencepiece_ohos.ps1 -Abi arm64-v8a' -ForegroundColor Cyan
    exit 1
}

$ct2 = Get-Item (Join-Path $LibDir 'libctranslate2.so')
$napi = Get-ChildItem (Join-Path $Root 'entry\build\default\intermediates\libs\default\arm64-v8a') -Filter 'libctranslate2_napi.so' -ErrorAction SilentlyContinue | Select-Object -First 1

Write-Host "[OK] entry\libs\$Abi\libctranslate2.so" $ct2.Length 'bytes' -ForegroundColor Green
if ($napi) {
    Write-Host "[OK] built napi" $napi.FullName $napi.Length 'bytes' -ForegroundColor Green
} else {
    Write-Host '[..] No built napi yet — run DevEco Build after this check' -ForegroundColor Yellow
}
Write-Host 'Then: DevEco Clean Project → Rebuild, uninstall app on phone, install new HAP.' -ForegroundColor Cyan
Write-Host 'Logcat should show: CT2 linked=true build=CTranslate2 linked (NLLB offline) abi=arm64-v8a' -ForegroundColor DarkGray
