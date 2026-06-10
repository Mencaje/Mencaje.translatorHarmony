# 打包格鲁吉亚语 / 德语 / 丹麦语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_ka_de_da_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso ka,de,da

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'ka,de,da'
Write-Host 'ka/de/da + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
