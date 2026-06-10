# Cross-compile libctranslate2.so for HarmonyOS (arm64-v8a / x86_64)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_ctranslate2_ohos.ps1 [-Abi arm64-v8a]

param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Ct2Root = Join-Path $Root 'CTranslate2'
if (-not (Test-Path (Join-Path $Ct2Root 'CMakeLists.txt'))) {
    Write-Host 'CTranslate2 source missing at third_party/CTranslate2 or CTranslate2/' -ForegroundColor Red
    exit 1
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
$BuildDir = Join-Path $Root "build\ctranslate2-ohos-$Abi"
$OutLib = Join-Path $Root "entry\libs\$Abi\libctranslate2.so"

New-Item -ItemType Directory -Path (Split-Path $OutLib) -Force | Out-Null
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }

Write-Host "Configure CTranslate2 for OHOS $Abi ..." -ForegroundColor Cyan
$cmakeArgs = @(
    '-S', $Ct2Root,
    '-B', $BuildDir,
    '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain",
    "-DCMAKE_MAKE_PROGRAM=$Ninja",
    "-DOHOS_ARCH=$Abi",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DWITH_MKL=OFF',
    '-DWITH_DNNL=OFF',
    '-DWITH_OPENBLAS=OFF',
    # Ruy SGEMM backend (required on CPU). cpuinfo uses src/ohos_stubs.c for arm64 OHOS.
    '-DWITH_RUY=ON',
    '-DOPENMP_RUNTIME=NONE',
    '-DBUILD_CLI=OFF',
    '-DBUILD_TESTS=OFF',
    '-DBUILD_SHARED_LIBS=ON',
    '-DENABLE_CPU_DISPATCH=OFF',
    '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
    '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF',
    '-DCMAKE_CXX_FLAGS=-D__OHOS__'
)
& $Cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Build libctranslate2.so ...' -ForegroundColor Cyan
& $Cmake --build $BuildDir --target ctranslate2 -j 8
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$built = Get-ChildItem -Path $BuildDir -Recurse -Filter 'libctranslate2.so*' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^libctranslate2\.so' -and $_.Length -gt 100000 } |
    Sort-Object Length -Descending |
    Select-Object -First 1
if (-not $built) {
    throw 'libctranslate2.so not found after build'
}
Copy-Item -Force $built.FullName $OutLib
# Runtime SONAME is libctranslate2.so.4 — ship alias beside the .so name.
$OutLib4 = Join-Path (Split-Path $OutLib) 'libctranslate2.so.4'
Copy-Item -Force $built.FullName $OutLib4
Write-Host "[ok] $OutLib ($([math]::Round((Get-Item $OutLib).Length/1MB, 1)) MB)" -ForegroundColor Green
Write-Host "[ok] $OutLib4" -ForegroundColor Green
