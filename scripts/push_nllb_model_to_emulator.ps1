# 将 NLLB 模型文件复制到电脑临时目录，供模拟器「从本机导入模型文件」使用。
# 说明：HarmonyOS 应用沙箱无法读取 /data/local/tmp，hdc 直推应用目录在多数模拟器上会失败。
#
# 用法（DevEco Terminal）:
#   powershell -ExecutionPolicy Bypass -File scripts\push_nllb_model_to_emulator.ps1
#
# 然后在应用中：设置 → 离线翻译模型 → 从本机导入模型文件
# 选中本脚本输出的文件夹中的四个文件（可多选）。

param(
    [string]$ModelDir = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ModelDir)) {
    $candidates = @(
        (Join-Path $Root 'third_party\models\nllb-resfile-stash\nllb-200-distilled-600M'),
        (Join-Path $Root 'third_party\models\nllb-ct2-download\nllb-200-distilled-600M'),
        (Join-Path $Root 'entry\src\main\resources\resfile\nllb-200-distilled-600M')
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'model.bin')) { $ModelDir = $c; break }
    }
}

if (-not (Test-Path (Join-Path $ModelDir 'model.bin'))) {
    Write-Host '[!] Model missing. Run: scripts\fetch_nllb_rawfile_model.ps1' -ForegroundColor Red
    exit 1
}

$exportDir = Join-Path $env:USERPROFILE 'Downloads\MencajeNllbModel'
New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

$files = @('config.json', 'shared_vocabulary.json', 'sentencepiece.bpe.model', 'model.bin')
foreach ($name in $files) {
    $src = Join-Path $ModelDir $name
    if (-not (Test-Path $src)) {
        Write-Host "[!] missing $name in $ModelDir" -ForegroundColor Red
        exit 1
    }
    Copy-Item -Force $src (Join-Path $exportDir $name)
}

Write-Host ''
Write-Host '[ok] Model files copied for picker import:' -ForegroundColor Green
Write-Host "  $exportDir" -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Yellow
Write-Host '  1. Rebuild and run the app on the emulator'
Write-Host '  2. Settings -> Offline NLLB model -> Import model files from device'
Write-Host '  3. Select all 4 files from the folder above (multi-select)'
Write-Host ''
Write-Host 'For one-shot install without import: restore_nllb_resfile_for_release.ps1, Wipe Data, Clean+Rebuild (~2.5GB HAP).' -ForegroundColor DarkGray
