# 吉尔吉斯语 RHVoice（声线 azamat + Kyrgyz 语言包）并打入 HAP rawfile
# 用法: .\scripts\pack_ky_rhvoice.ps1
# 朗读还需: scripts\build_rhvoice_ohos.ps1 将 libRHVoice.so 放入 entry/libs 后 Clean 重编

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Root 'scripts\setup_rhvoice_kyrgyz.ps1')
Write-Host 'ky RHVoice data packed. Rebuild HAP; for synthesis also build libRHVoice (build_rhvoice_ohos.ps1).' -ForegroundColor Green
