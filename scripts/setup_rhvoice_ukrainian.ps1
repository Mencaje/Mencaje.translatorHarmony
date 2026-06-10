# 下载乌克兰语 RHVoice（声线 natalia + Ukrainian 语言包），合并到 pack/ 并打包 rawfile
# 可与俄/英并存：只更新 voices/natalia 与 languages/Ukrainian，不删除其它语种
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_ukrainian.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_uk_setup'
# GitHub 需外网；rhvoice.org 为备用（国内/无外网时更稳）
$VoiceUrls = @(
    'https://github.com/RHVoice/natalia-ukr/releases/download/v4.1/RHVoice-voice-Ukrainian-Natalia-4.1.1014.10.nvda-addon',
    'https://rhvoice.org/download/RHVoice-voice-Ukrainian-Natalia-v4.0.zip'
)
$LangUrl = 'https://rhvoice.org/download/RHVoice-language-Ukrainian-v1.13.zip'

function Expand-ZipEntryPrefix {
    param(
        [string]$ZipPath,
        [string]$DestDir,
        [string]$Prefix = ''
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    foreach ($e in $zip.Entries) {
        if ($e.FullName.EndsWith('/')) { continue }
        $rel = $e.FullName
        if ($Prefix.Length -gt 0) {
            if (-not $rel.StartsWith($Prefix)) { continue }
            $rel = $rel.Substring($Prefix.Length)
        }
        $out = Join-Path $DestDir $rel
        $dir = Split-Path $out -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
    }
    $zip.Dispose()
}

function Get-Archive {
    param([string]$OutFile, [string[]]$Urls, [long]$MinBytes = 50000)
    if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
        Write-Host "OK (cached): $OutFile" -ForegroundColor Green
        return
    }
    $lastErr = $null
    foreach ($Url in $Urls) {
        Write-Host "Downloading $Url ..." -ForegroundColor Cyan
        $tmp = "$OutFile.part"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        curl.exe -L --retry 3 --connect-timeout 90 -o $tmp $Url
        if ((Test-Path $tmp) -and (Get-Item $tmp).Length -ge $MinBytes) {
            Move-Item -Force $tmp $OutFile
            Write-Host "Saved $OutFile ($((Get-Item $OutFile).Length) bytes)" -ForegroundColor Green
            return
        }
        $lastErr = $Url
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
    throw "Download failed or too small: $lastErr"
}

if (Test-Path $Cache) { Remove-Item -Recurse -Force $Cache }
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
New-Item -ItemType Directory -Path $PackVoices -Force | Out-Null
New-Item -ItemType Directory -Path $PackLangs -Force | Out-Null

$voiceZip = Join-Path $Cache 'natalia.zip'
$langZip = Join-Path $Cache 'ukrainian-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls @($LangUrl) -MinBytes 50000

$nataliaDir = Join-Path $PackVoices 'natalia'
if (Test-Path $nataliaDir) { Remove-Item -Recurse -Force $nataliaDir }
New-Item -ItemType Directory -Path $nataliaDir -Force | Out-Null
Write-Host 'Extract voice natalia ...' -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $nataliaDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $nataliaDir
}

$ukLangDir = Join-Path $PackLangs 'Ukrainian'
if (Test-Path $ukLangDir) { Remove-Item -Recurse -Force $ukLangDir }
New-Item -ItemType Directory -Path $ukLangDir -Force | Out-Null
Write-Host 'Extract language Ukrainian ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $ukLangDir

if (-not (Test-Path (Join-Path $nataliaDir 'voice.info'))) {
    throw 'Missing voices/natalia/voice.info after extract'
}
if (-not (Test-Path (Join-Path $ukLangDir 'language.info'))) {
    throw 'Missing languages/Ukrainian/language.info after extract'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Ukrainian RHVoice (natalia) packed. Clean + Rebuild HAP, reinstall app, install Ukrainian in TTS voice screen.' -ForegroundColor Green
