# 将 SummerTTS 中文模型打入 HAP rawfile（约 76 MB）
# 用法: .\scripts\pack_summertts_zh_rawfile.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Src = Join-Path $Root 'third_party\tts\SummerTTS\models\single_speaker_fast.bin'
$DestDir = Join-Path $Root 'entry\src\main\resources\rawfile'
$Dest = Join-Path $DestDir 'summer_single_speaker_fast.bin'

if (-not (Test-Path $Src)) {
    Write-Error "Missing model: $Src`nClone SummerTTS and ensure models/single_speaker_fast.bin exists."
}
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
Copy-Item -Force $Src $Dest
$mb = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
Write-Host "Packed Chinese SummerTTS -> $Dest ($mb MB)"
