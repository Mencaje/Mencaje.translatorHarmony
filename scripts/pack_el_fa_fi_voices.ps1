# 打包希腊语 / 波斯语 / 芬兰语 Piper 语音 + espeak 词典
# 用法: .\scripts\pack_el_fa_fi_voices.ps1
# 需已执行: .\scripts\setup_piper_voices.ps1 -Iso el,fa,fi

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\pack_espeak_data.ps1')
& (Join-Path $Root 'scripts\pack_piper_voices.ps1') -Iso 'el,fa,fi'
Write-Host 'el/fa/fi + espeak packed. DevEco Clean + Rebuild, then test in 朗读语言.' -ForegroundColor Green
