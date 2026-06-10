# 清除 piper/Sherpa native 的 hvigor 增量缓存（避免 ProcessLibs 仍查找 libpiper_plus.so.1）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\clean_native_tts_build.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Remove-IfExists([string]$path) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
        Write-Host "Removed: $path"
    }
}

# hvigor 会缓存 base_native_libs.json 里的 .so.1 路径
Remove-IfExists (Join-Path $root 'entry\build\default\intermediates\patch\default')
Remove-IfExists (Join-Path $root 'entry\.cxx')
Remove-IfExists (Join-Path $root '.hvigor\cache')

$patterns = @('libpiper_plus.so.1', 'libpiper_plus.so.1.12.0')
$searchRoots = @(
    (Join-Path $root 'entry\build\default\intermediates\libs'),
    (Join-Path $root 'entry\build\default\intermediates\stripped_native_libs'),
    (Join-Path $root 'entry\build\default\intermediates\cmake\default\obj')
)
foreach ($dir in $searchRoots) {
    if (-not (Test-Path $dir)) { continue }
    foreach ($pat in $patterns) {
        Get-ChildItem -Path $dir -Recurse -Filter $pat -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -Force $_.FullName; Write-Host "Removed: $($_.FullName)" }
    }
}

# 勿在 entry/libs 放 piper（仅 Sherpa 预编译库）
$libsPiper = Join-Path $root 'entry\libs\arm64-v8a\libpiper_plus.so'
if (Test-Path $libsPiper) {
    Remove-Item -Force $libsPiper
    Write-Host "Removed: $libsPiper"
}

Write-Host 'Done. Rebuild in DevEco (Build -> Rebuild Project).'
