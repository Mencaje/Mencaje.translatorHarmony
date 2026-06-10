# 一键：NLLB 压缩包 → rawfile（编入 HAP，首启自动解压，满足商店 <4GB 包体）
# Usage: powershell -ExecutionPolicy Bypass -File scripts\prepare_nllb_for_hap.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
& (Join-Path $Root 'scripts\fetch_nllb_rawfile_model.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
