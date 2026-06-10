# 打包斯洛伐克语 / 斯洛文尼亚语 / 塞尔维亚语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_sk_sl_sr_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso sk,sl,sr

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'sk,sl,sr'
Write-Host 'sk/sl/sr + espeak packed. DevEco Clean + Rebuild.' -ForegroundColor Green
