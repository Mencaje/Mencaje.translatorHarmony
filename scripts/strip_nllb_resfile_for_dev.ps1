# 把 NLLB 从 HAP 资源中挪走，减小包体（约减 0.6–2.3GB）。
# 用途：模拟器磁盘不足(9568288)；HAP>4GB 时 SignHap 报 11017001 zip64 无法签名。
# 装完小包后运行: scripts\push_nllb_model_to_emulator.ps1
# 上架前恢复: scripts\restore_nllb_resfile_for_release.ps1
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\strip_nllb_resfile_for_dev.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$BundleInRes = Join-Path $Root 'entry\src\main\resources\resfile\nllb-200-distilled-600M'
$ZipInRaw = Join-Path $Root 'entry\src\main\resources\rawfile\nllb200_distilled_600m.zip'
$StashDir = Join-Path $Root 'third_party\models\nllb-resfile-stash'
$StashBundle = Join-Path $StashDir 'nllb-200-distilled-600M'
$StashZip = Join-Path $StashDir 'nllb200_distilled_600m.zip'

$moved = $false
New-Item -ItemType Directory -Path $StashDir -Force | Out-Null

if (Test-Path (Join-Path $BundleInRes 'model.bin')) {
    if (Test-Path $StashBundle) { Remove-Item -Recurse -Force $StashBundle }
    Move-Item -Path $BundleInRes -Destination $StashBundle
    Write-Host '[ok] Moved resfile folder to stash:' $StashBundle -ForegroundColor Green
    $moved = $true
}

if (Test-Path $ZipInRaw) {
    if (Test-Path $StashZip) { Remove-Item -Force $StashZip }
    Move-Item -Path $ZipInRaw -Destination $StashZip
    Write-Host '[ok] Moved rawfile zip to stash:' $StashZip -ForegroundColor Green
    $moved = $true
}

if (-not $moved) {
    if ((Test-Path (Join-Path $StashBundle 'model.bin')) -or (Test-Path $StashZip)) {
        Write-Host '[skip] NLLB already stripped; stash under third_party\models\nllb-resfile-stash' -ForegroundColor Green
        exit 0
    }
    Write-Host '[!] No NLLB in HAP resources — run fetch_nllb_rawfile_model.ps1 first' -ForegroundColor Red
    exit 1
}

Write-Host 'Next: DevEco Clean + Rebuild, install HAP, then:' -ForegroundColor Cyan
Write-Host '  powershell -File scripts\push_nllb_model_to_emulator.ps1' -ForegroundColor Cyan
