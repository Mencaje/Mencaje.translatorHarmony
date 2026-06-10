# 打包波兰语 / 葡萄牙语 Piper 语音 + espeak 词典（首次或更新模型后运行）
# 用法: .\scripts\pack_pl_es_pt_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso pl,pt

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'pl,pt'
Write-Host 'pl/pt + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
