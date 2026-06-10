# 下载 OpenHarmony 预编译 ONNX Runtime（arm64-v8a + x86_64），供 piper-plus 日语 TTS
# 放入 third_party/ohos/onnxruntime/prebuilt/<abi>/（不放入 entry/libs，避免与 CMake 产物重复打包）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\setup_onnxruntime_ohos.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Version = '1.16.3'
$CacheDir = Join-Path $Root 'third_party\ohos\onnxruntime'
$PrebuiltRoot = Join-Path $CacheDir 'prebuilt'

function Install-OrtAbi {
    param(
        [string]$AbiFolder,
        [string]$ZipSuffix
    )
    $ZipName = "onnxruntime-ohos-$ZipSuffix-$Version.zip"
    $Url = "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v$Version/$ZipName"
    $Extracted = Join-Path $CacheDir "onnxruntime-ohos-$ZipSuffix-$Version"
    $SoPath = Join-Path $Extracted 'lib\libonnxruntime.so'

    if (-not (Test-Path $SoPath)) {
        $zipPath = Join-Path $CacheDir $ZipName
        if (-not (Test-Path $zipPath)) {
            Write-Host "[download] $Url" -ForegroundColor Cyan
            try {
                Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing
            } catch {
                Write-Host "[!] Failed to download $ZipName — piper-plus on $AbiFolder will be skipped." -ForegroundColor Yellow
                return $false
            }
        }
        if (Test-Path $zipPath) {
            Expand-Archive -Path $zipPath -DestinationPath $CacheDir -Force
        }
    }

    if (-not (Test-Path $SoPath)) {
        Write-Host "[!] Missing $SoPath after extract" -ForegroundColor Yellow
        return $false
    }

    $dst = Join-Path $PrebuiltRoot $AbiFolder
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item $SoPath (Join-Path $dst 'libonnxruntime.so') -Force

    # 清理 entry/libs 中旧副本，避免 ProcessLibs 报 Duplicated files
    $legacy = Join-Path $Root "entry\libs\$AbiFolder\libonnxruntime.so"
    if (Test-Path $legacy) {
        Remove-Item -Force $legacy
        Write-Host "[cleanup] removed duplicate $legacy" -ForegroundColor DarkYellow
    }

    Write-Host "[ok] libonnxruntime.so -> $dst" -ForegroundColor Green
    return $true
}

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

$armOk = Install-OrtAbi -AbiFolder 'arm64-v8a' -ZipSuffix 'arm64-v8a'
$x86Ok = Install-OrtAbi -AbiFolder 'x86_64' -ZipSuffix 'x86_64'

$armExtracted = Join-Path $CacheDir "onnxruntime-ohos-arm64-v8a-$Version"
$incDst = Join-Path $CacheDir 'include'
if ($armOk -and (Test-Path (Join-Path $armExtracted 'include')) -and -not (Test-Path $incDst)) {
    Copy-Item -Recurse (Join-Path $armExtracted 'include') $incDst -Force
}
if (-not (Test-Path $incDst)) {
    $x86Extracted = Join-Path $CacheDir "onnxruntime-ohos-x86_64-$Version"
    if (Test-Path (Join-Path $x86Extracted 'include')) {
        Copy-Item -Recurse (Join-Path $x86Extracted 'include') $incDst -Force
    }
}

$stamp = Join-Path $CacheDir 'onnxruntime_headers_ready.stamp'
Set-Content -Path $stamp -Value "ok arm=$armOk x86=$x86Ok $(Get-Date -Format o)" -Encoding ascii

if (-not $armOk -and -not $x86Ok) {
    Write-Host '[!] No ONNX Runtime installed.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'ORT prebuilt: third_party\ohos\onnxruntime\prebuilt\<abi>\libonnxruntime.so' -ForegroundColor Cyan
Write-Host 'Next: prepare_native_tts.ps1 then DevEco Clean + Rebuild' -ForegroundColor Cyan
