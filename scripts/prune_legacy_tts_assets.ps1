# 删除 HAP 中已不再使用的 TTS 资源（Sherpa/Silero NC），并去掉与 resfile 重复的 piper zip
# 当前栈：zh=SummerTTS, ja=piper-plus(resfile), 多语=RHVoice
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\prune_legacy_tts_assets.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'
$ResDir = Join-Path $Root 'entry\src\main\resources\resfile'

$remove = @(
    'sherpa_en_vits.zip',
    'sherpa_de_vits.zip',
    'sherpa_es_vits.zip',
    'sherpa_fr_vits.zip',
    'sherpa_ru_vits.zip',
    'silero_v3_en.pt',
    'silero_v3_en_mobile.ptl',
    'silero_en_lj_16k.onnx',
    'piperplus_ja_voice.zip'
)

$freed = 0
foreach ($name in $remove) {
    $p = Join-Path $RawDir $name
    if (Test-Path $p) {
        $freed += (Get-Item $p).Length
        Remove-Item -Force $p
        Write-Host "removed rawfile/$name" -ForegroundColor Yellow
    }
}

$resPiper = Join-Path $ResDir 'piperplus_ja_voice.zip'
if (-not (Test-Path $resPiper)) {
    $rawPiper = Join-Path $RawDir 'piperplus_ja_voice.zip'
    if (Test-Path $rawPiper) {
        Write-Host '[!] resfile missing piper — run pack_piperplus_ja_rawfile.ps1' -ForegroundColor Red
    }
}

$mb = [math]::Round($freed / 1MB, 1)
Write-Host "[ok] freed ~$mb MB from rawfile. Clean + Rebuild HAP before deploy." -ForegroundColor Green
