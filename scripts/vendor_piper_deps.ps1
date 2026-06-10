# 预下载 piper-plus 构建依赖（fmt / spdlog），避免 HAP 编译时访问 GitHub 失败。
# Usage: powershell -ExecutionPolicy Bypass -File scripts\vendor_piper_deps.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Vendor = Join-Path $Root 'third_party\tts\piper-plus\vendor'
New-Item -ItemType Directory -Path $Vendor -Force | Out-Null

function Get-Archive {
    param(
        [string]$OutFile,
        [string[]]$Urls,
        [long]$MinBytes = 100000
    )
    if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
        Write-Host "OK (cached): $OutFile" -ForegroundColor Green
        return
    }
    foreach ($url in $Urls) {
        Write-Host "Downloading $url ..." -ForegroundColor Cyan
        $tmp = "$OutFile.part"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        & curl.exe -L --retry 3 --connect-timeout 30 -o $tmp $url
        if ((Test-Path $tmp) -and (Get-Item $tmp).Length -ge $MinBytes) {
            Move-Item -Force $tmp $OutFile
            Write-Host "Saved $OutFile ($((Get-Item $OutFile).Length) bytes)" -ForegroundColor Green
            return
        }
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
    throw "Failed to download $OutFile"
}

$fmtUrls = @(
    'https://ghproxy.net/https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.zip',
    'https://mirror.ghproxy.com/https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.zip',
    'https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.zip'
)
$spdUrls = @(
    'https://ghproxy.net/https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.zip',
    'https://mirror.ghproxy.com/https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.zip',
    'https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.zip'
)

Get-Archive -OutFile (Join-Path $Vendor 'fmt-10.0.0.zip') -Urls $fmtUrls
Get-Archive -OutFile (Join-Path $Vendor 'spdlog-1.12.0.zip') -Urls $spdUrls
Write-Host 'Done. Rebuild HAP in DevEco.' -ForegroundColor Cyan
