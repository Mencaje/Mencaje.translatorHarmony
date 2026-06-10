# 上架/完整包：把 stash 或 cache 里的 NLLB 打成 rawfile zip 编入 HAP（推荐，<4GB）
# 可选 -IncludeResfile：同时恢复 2.4GB 明文 resfile（仅本机调试，易超 4GB）
# Usage: powershell -ExecutionPolicy Bypass -File scripts\restore_nllb_resfile_for_release.ps1

param([switch]$IncludeResfile)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$fetch = Join-Path $Root 'scripts\fetch_nllb_rawfile_model.ps1'
if (-not (Test-Path $fetch)) {
    Write-Host '[!] missing fetch_nllb_rawfile_model.ps1' -ForegroundColor Red
    exit 1
}
if ($IncludeResfile) {
    & $fetch -IncludeResfile
} else {
    & $fetch
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host '[ok] Release bundle: rawfile/nllb200_distilled_600m.zip ready for HAP' -ForegroundColor Green
