# 打包马拉雅拉姆语 / 尼泊尔语 Piper 语音（波兰语 pl 已在 resfile/piper_pl_voice.zip）
# 用法: .\scripts\pack_ml_ne_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso ml,ne

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'ml,ne'
Write-Host 'ml/ne + espeak packed. pl already in resfile. Clean + Rebuild.' -ForegroundColor Green
