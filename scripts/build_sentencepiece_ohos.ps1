# Cross-compile libsentencepiece.a for HarmonyOS (static, linked into ctranslate2_napi)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_sentencepiece_ohos.ps1 [-Abi x86_64]

param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$SpmRoot = Join-Path $Root 'third_party\sentencepiece'
if (-not (Test-Path (Join-Path $SpmRoot 'CMakeLists.txt'))) {
    Write-Host 'Cloning sentencepiece v0.2.0 ...' -ForegroundColor Cyan
    git clone --depth 1 --branch v0.2.0 https://github.com/google/sentencepiece.git $SpmRoot
}

$NDK = 'D:\deveco studio\sdk\default\openharmony\native'
if ($env:OHOS_SDK_NATIVE) { $NDK = $env:OHOS_SDK_NATIVE }
if (-not (Test-Path $NDK)) {
    Write-Host "OHOS NDK not found at $NDK" -ForegroundColor Red
    exit 1
}

$Cmake = Join-Path $NDK 'build-tools\cmake\bin\cmake.exe'
$Ninja = Join-Path $NDK 'build-tools\cmake\bin\ninja.exe'
$Toolchain = Join-Path $NDK 'build\cmake\ohos.toolchain.cmake'
$BuildDir = Join-Path $Root "build\sentencepiece-ohos-$Abi"
$OutLib = Join-Path $Root "entry\libs\$Abi\libsentencepiece.a"

New-Item -ItemType Directory -Path (Split-Path $OutLib) -Force | Out-Null
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }

Write-Host "Configure SentencePiece for OHOS $Abi ..." -ForegroundColor Cyan
$cmakeArgs = @(
    '-S', $SpmRoot,
    '-B', $BuildDir,
    '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain",
    "-DCMAKE_MAKE_PROGRAM=$Ninja",
    "-DOHOS_ARCH=$Abi",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DSPM_ENABLE_SHARED=OFF',
    '-DSPM_ENABLE_TCMALLOC=OFF',
    '-DSPM_BUILD_TEST=OFF',
    '-DCMAKE_POSITION_INDEPENDENT_CODE=ON'
)
& $Cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Build libsentencepiece.a ...' -ForegroundColor Cyan
& $Cmake --build $BuildDir --target sentencepiece-static -j 8
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$built = Get-ChildItem -Path $BuildDir -Recurse -Filter 'libsentencepiece.a' -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 1
if (-not $built) {
    throw 'libsentencepiece.a not found after build'
}
Copy-Item -Force $built.FullName $OutLib
Write-Host "[ok] $OutLib ($([math]::Round((Get-Item $OutLib).Length/1MB, 1)) MB)" -ForegroundColor Green
