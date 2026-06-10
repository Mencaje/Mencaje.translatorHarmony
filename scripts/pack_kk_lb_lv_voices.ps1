# 打包哈萨克语 / 卢森堡语 / 拉脱维亚语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_kk_lb_lv_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso kk,lb,lv

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'kk,lb,lv'
Write-Host 'kk/lb/lv + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
