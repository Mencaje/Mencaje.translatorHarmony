# Verify Sherpa libs and arm64 native build flags.
# Usage: .\scripts\verify_sherpa_native.ps1 [-FixCxx]

param(
    [switch]$FixCxx
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LibDir = Join-Path $Root 'entry\libs\arm64-v8a'
$Stamp = Join-Path $Root 'third_party\ohos\sherpa\sherpa_headers_ready.stamp'
$CxxArm64 = Join-Path $Root 'entry\.cxx\default\default\debug\arm64-v8a'
$CompileDb = Join-Path $CxxArm64 'compile_commands.json'
$Required = @(
    @{ Name = 'libsherpa-onnx-c-api.so'; MinMB = 2 },
    @{ Name = 'libonnxruntime.so'; MinMB = 8 },
    @{ Name = 'libsherpa_onnx.so'; MinMB = 0.1 }
)

Write-Host '=== Sherpa / Silero native check ===' -ForegroundColor Cyan
$ok = $true

foreach ($item in $Required) {
    $p = Join-Path $LibDir $item.Name
    if (-not (Test-Path $p)) {
        Write-Host "[MISSING] $($item.Name) in $LibDir" -ForegroundColor Red
        $ok = $false
    } else {
        $mb = [math]::Round((Get-Item $p).Length / 1MB, 1)
        if ($mb -lt $item.MinMB) {
            Write-Host "[BAD] $($item.Name) too small (${mb} MB)" -ForegroundColor Red
            $ok = $false
        } else {
            Write-Host "[OK] $($item.Name) ${mb} MB" -ForegroundColor Green
        }
    }
}

if (-not (Test-Path $Stamp)) {
    Write-Host "[MISSING] $Stamp - run: .\scripts\setup_sherpa_ohos.ps1" -ForegroundColor Red
    $ok = $false
} else {
    Write-Host '[OK] sherpa headers stamp' -ForegroundColor Green
}

if (Test-Path $CompileDb) {
    $json = Get-Content $CompileDb -Raw -Encoding UTF8
    if ($json -match 'SILERO_USE_SHERPA_ONNX') {
        Write-Host '[OK] arm64 compile_commands has SILERO_USE_SHERPA_ONNX' -ForegroundColor Green
    } else {
        Write-Host '[WARN] arm64 compile_commands missing SILERO_USE_SHERPA_ONNX (stale CMake cache?)' -ForegroundColor Yellow
        $ok = $false
    }
} else {
    Write-Host '[INFO] no compile_commands yet (arm64 debug not built locally)' -ForegroundColor Yellow
}

$hapSo = Join-Path $Root 'entry\build\default\intermediates\cmake\default\obj\arm64-v8a\libsilero_tts_napi.so'
if (Test-Path $hapSo) {
    $bytes = [System.IO.File]::ReadAllBytes($hapSo)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    if ($text -match '\[sherpa-v1\]') {
        Write-Host '[OK] built libsilero_tts_napi.so is Sherpa-linked ([sherpa-v1])' -ForegroundColor Green
    } elseif ($text -match 'NO inference') {
        Write-Host '[FAIL] built libsilero_tts_napi.so is stub (no inference linked)' -ForegroundColor Red
        Write-Host '       DevEco: Clean Project + Rebuild, or run this script with -FixCxx' -ForegroundColor Yellow
        $ok = $false
    } else {
        Write-Host '[WARN] libsilero_tts_napi.so found but no [sherpa-v1] marker' -ForegroundColor Yellow
        $ok = $false
    }
}

if ($FixCxx -and (Test-Path (Join-Path $Root 'entry\.cxx'))) {
    Write-Host '[ACTION] removing entry\.cxx to force CMake reconfigure...' -ForegroundColor Yellow
    Remove-Item -Recurse -Force (Join-Path $Root 'entry\.cxx')
    Write-Host '[DONE] deleted entry\.cxx - Clean + Rebuild in DevEco' -ForegroundColor Green
}

Write-Host ''
if (-not $ok) {
    Write-Host 'NOT READY. Run .\scripts\prepare_native_tts.ps1 then DevEco Clean + Rebuild.' -ForegroundColor Red
    exit 1
}
Write-Host 'Local checks passed. DevEco Clean + Rebuild, then install on device.' -ForegroundColor Green
exit 0
