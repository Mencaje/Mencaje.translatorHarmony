# Cross-compile libRHVoice.so for HarmonyOS (arm64-v8a / x86_64)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_rhvoice_ohos.ps1 [-Abi arm64-v8a]

param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RhvRoot = Join-Path $Root 'third_party\rhvoice'
$ApiH = Join-Path $RhvRoot 'src\include\RHVoice.h'
if (-not (Test-Path $ApiH)) {
    Write-Host 'RHVoice source missing — run scripts\setup_rhvoice.ps1 first.' -ForegroundColor Red
    exit 1
}

$NDK = 'D:\deveco studio\sdk\default\openharmony\native'
if (-not (Test-Path $NDK)) {
    Write-Host "OHOS NDK not found at $NDK — set OHOS_SDK_NATIVE or install DevEco SDK." -ForegroundColor Red
    exit 1
}

$Cmake = Join-Path $NDK 'build-tools\cmake\bin\cmake.exe'
$Ninja = Join-Path $NDK 'build-tools\cmake\bin\ninja.exe'
$Toolchain = Join-Path $NDK 'build\cmake\ohos.toolchain.cmake'
$BuildDir = Join-Path $Root "build\rhvoice-ohos-$Abi"
$OutLib = Join-Path $Root "entry\libs\$Abi\libRHVoice.so"

New-Item -ItemType Directory -Path (Split-Path $OutLib) -Force | Out-Null

if (Test-Path $BuildDir) {
    Remove-Item -Recurse -Force $BuildDir
}

Write-Host "Configure RHVoice for OHOS $Abi ..." -ForegroundColor Cyan
$cmakeArgs = @(
    '-S', $RhvRoot,
    '-B', $BuildDir,
    '-G', 'Ninja',
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain",
    "-DCMAKE_MAKE_PROGRAM=$Ninja",
    "-DOHOS_ARCH=$Abi",
    '-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_CLIENT=OFF',
    '-DBUILD_SERVICE=OFF',
    '-DBUILD_TESTS=OFF',
    '-DBUILD_UTILS=OFF',
    '-DBUILD_SPEECHDISPATCHER_MODULE=OFF',
    '-DWITH_DATA=OFF',
    '-DENABLE_SONIC=OFF',
    '-DWITH_LIBAO=OFF',
    '-DWITH_PULSE=OFF',
    '-DWITH_PORTAUDIO=OFF',
    '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY',
    '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF'
)
& $Cmake @cmakeArgs

Write-Host 'Build libRHVoice.so ...' -ForegroundColor Cyan
& $Cmake --build $BuildDir --target RHVoice -j 8

function Install-RhvSo {
    param([string]$RelUnderBuild, [string]$OutPath)
    $candidates = @(
        (Join-Path $BuildDir $RelUnderBuild),
        (Join-Path $BuildDir ($RelUnderBuild + '.1.18.4'))
    )
    $src = $null
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and (Get-Item $c).Length -gt 1000) { $src = $c; break }
    }
    if (-not $src) {
        $leaf = Split-Path $RelUnderBuild -Leaf
        $src = (Get-ChildItem -Path $BuildDir -Recurse -Filter "$leaf*" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 1000 } |
            Sort-Object Length -Descending |
            Select-Object -First 1).FullName
    }
    if (-not $src) { throw "Not found: $RelUnderBuild under $BuildDir" }
    Copy-Item $src $OutPath -Force
    Write-Host "Installed $OutPath ($((Get-Item $OutPath).Length) bytes) from $src" -ForegroundColor Green
}

Install-RhvSo -RelUnderBuild 'src\lib\libRHVoice.so' -OutPath $OutLib
$coreOut = Join-Path (Split-Path $OutLib) 'libRHVoice_core.so'
Install-RhvSo -RelUnderBuild 'src\core\libRHVoice_core.so' -OutPath $coreOut

$FixAliases = Join-Path $Root 'scripts\fix_rhvoice_soname_aliases.ps1'
if (Test-Path $FixAliases) {
    & $FixAliases -Abi $Abi
}

Write-Host 'Rebuild HAP; HiLog build= should include [rhvoice].' -ForegroundColor Cyan
