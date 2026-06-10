# RHVoice 的 ELF SONAME 为 libRHVoice.so.1 / libRHVoice_core.so.1。
# HarmonyOS 加载 libsilero_tts_napi.so 时需要同目录存在该文件名（不能只放 libRHVoice.so）。
param(
    [ValidateSet('arm64-v8a', 'x86_64', '')]
    [string]$Abi = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$abis = if ($Abi.Length -gt 0) { @($Abi) } else { @('arm64-v8a', 'x86_64') }

foreach ($oneAbi in $abis) {
    $dir = Join-Path $Root "entry\libs\$oneAbi"
    if (-not (Test-Path $dir)) {
        Write-Host "Skip $oneAbi — missing $dir" -ForegroundColor Yellow
        continue
    }
    foreach ($base in @('libRHVoice.so', 'libRHVoice_core.so')) {
        $src = Join-Path $dir $base
        if (-not (Test-Path $src)) {
            Write-Host "Skip $oneAbi\$base (not found)" -ForegroundColor Yellow
            continue
        }
        $alias = $base -replace '\.so$', '.so.1'
        $dst = Join-Path $dir $alias
        Copy-Item $src $dst -Force
        Write-Host "OK $oneAbi\$alias <- $base" -ForegroundColor Green
    }
}

Write-Host 'Soname aliases ready. Clean+Rebuild HAP and reinstall.' -ForegroundColor Cyan
