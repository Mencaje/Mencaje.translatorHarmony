# 一键准备离线 TTS：中文 SummerTTS、日语 piper-plus、Piper 多语（已剔除 RHVoice GPL-2.0 / Sherpa/Silero NC）

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)



$Prune = Join-Path $Root 'scripts\prune_legacy_tts_assets.ps1'

if (Test-Path $Prune) {

    Write-Host '[prune] remove legacy Sherpa/Silero rawfile (saves ~400MB HAP)...' -ForegroundColor Cyan

    & $Prune

}



$PackZh = Join-Path $Root 'scripts\pack_summertts_zh_rawfile.ps1'

$PackJa = Join-Path $Root 'scripts\pack_piperplus_ja_rawfile.ps1'

$PackEspeak = Join-Path $Root 'scripts\pack_espeak_data.ps1'

$SetupOrt = Join-Path $Root 'scripts\setup_onnxruntime_ohos.ps1'

$VendorPiper = Join-Path $Root 'scripts\vendor_piper_deps.ps1'



if (Test-Path $PackZh) { & $PackZh }

if (Test-Path $PackJa) { & $PackJa }

if (Test-Path $PackEspeak) {

    Write-Host "[espeak] pack espeak-ng-data for Piper espeak voices..." -ForegroundColor Cyan

    & $PackEspeak

}

if (Test-Path $VendorPiper) {

    Write-Host "[piper] vendor fmt/spdlog (offline build)..." -ForegroundColor Cyan

    & $VendorPiper

}

if (Test-Path $SetupOrt) {

    Write-Host "[onnxruntime] for piper-plus ja..." -ForegroundColor Cyan

    & $SetupOrt

}

$SetupPiper = Join-Path $Root 'scripts\setup_piper_voices.ps1'
$PackPiper = Join-Path $Root 'scripts\pack_piper_voices.ps1'
$CorePiperIsos = 'ru,en,uk'
if (Test-Path $SetupPiper) {
    Write-Host "[piper] core voices ru/en/uk -> third_party/ohos/piper_voices ..." -ForegroundColor Cyan
    & $SetupPiper -Iso $CorePiperIsos
}
if (Test-Path $PackPiper) {
    Write-Host "[piper] pack core voices to resfile ..." -ForegroundColor Cyan
    & $PackPiper -Iso $CorePiperIsos
}
Write-Host "[piper] other langs: setup_piper_voices.ps1 -Iso pl,es,pt,ka,ar,..." -ForegroundColor DarkGray



Write-Host ""

Write-Host "Native libs per ABI under entry\libs\arm64-v8a\ and entry\libs\x86_64\:" -ForegroundColor Yellow

Write-Host "  libonnxruntime.so + libpiper_plus.so (piper-plus)" -ForegroundColor Yellow

Write-Host "下一步: DevEco Clean + Rebuild -> 卸载旧 App -> 安装新 HAP" -ForegroundColor Cyan

Write-Host "HiLog build= on arm64/x86 should include [summertts+piperplus] when all libs present" -ForegroundColor Cyan

