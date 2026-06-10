# 打包荷兰语 / 挪威语 / 罗马尼亚语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_nl_no_ro_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso nl,no,ro

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'nl,no,ro'
Write-Host 'nl/no/ro + espeak packed. DevEco Clean + Rebuild.' -ForegroundColor Green
