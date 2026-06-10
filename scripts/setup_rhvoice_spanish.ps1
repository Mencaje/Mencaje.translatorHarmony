# 下载西班牙语 RHVoice（声线 mateo + Spanish 语言包），合并到 pack/ 并打包 rawfile
# 可与俄/英/乌/波等并存：只更新 voices/mateo 与 languages/Spanish
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_spanish.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_es_setup'
$VoiceUrls = @(
    'https://github.com/RHVoice/mateo-spa/releases/download/4.14/RHVoice-voice-Spanish-Mateo-4.14.1041.12.nvda-addon',
    'https://github.com/RHVoice/mateo-spa/releases/download/4.14/RHVoice-voice-Spanish-Mateo-v4.14.zip'
)
$LangUrls = @(
    'https://github.com/RHVoice/spanish-bin/releases/download/1.41/RHVoice-language-Spanish-v1.41.zip',
    'https://rhvoice.org/download/RHVoice-language-Spanish-v1.0.zip'
)

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

$voiceZip = Join-Path $Cache 'mateo.zip'
$langZip = Join-Path $Cache 'spanish-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls $LangUrls -MinBytes 50000

$mateoDir = Join-Path $PackVoices 'mateo'
if (Test-Path $mateoDir) { Remove-Item -Recurse -Force $mateoDir }
New-Item -ItemType Directory -Path $mateoDir -Force | Out-Null
Write-Host 'Extract voice mateo ...' -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $mateoDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $mateoDir
}

$esLangDir = Join-Path $PackLangs 'Spanish'
if (Test-Path $esLangDir) { Remove-Item -Recurse -Force $esLangDir }
New-Item -ItemType Directory -Path $esLangDir -Force | Out-Null
Write-Host 'Extract language Spanish ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $esLangDir

if (-not (Test-Path (Join-Path $mateoDir 'voice.info'))) {
    throw 'Missing voices/mateo/voice.info after extract'
}
if (-not (Test-Path (Join-Path $esLangDir 'language.info'))) {
    throw 'Missing languages/Spanish/language.info after extract'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Spanish RHVoice (mateo) packed. Clean + Rebuild HAP, reinstall app, install Spanish in TTS voice screen.' -ForegroundColor Green
