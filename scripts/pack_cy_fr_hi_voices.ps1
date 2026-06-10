# 打包威尔士语 / 法语 / 印地语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_cy_fr_hi_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso cy,fr,hi

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'cy,fr,hi'
Write-Host 'cy/fr/hi + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
