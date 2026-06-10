# 打包匈牙利语 / 冰岛语 / 意大利语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_hu_is_it_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso hu,is,it

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'hu,is,it'
Write-Host 'hu/is/it + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
