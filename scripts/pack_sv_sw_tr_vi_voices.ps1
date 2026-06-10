# 打包瑞典语 / 斯瓦希里语 / 土耳其语 / 越南语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_sv_sw_tr_vi_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso "sv,sw,tr,vi"

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'sv,sw,tr,vi'
Write-Host 'sv/sw/tr/vi + espeak packed. DevEco Clean + Rebuild.' -ForegroundColor Green
