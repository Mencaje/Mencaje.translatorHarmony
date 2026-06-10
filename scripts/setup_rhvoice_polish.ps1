# 下载波兰语 RHVoice（声线 natan + Polish 语言包），合并到 pack/ 并打包 rawfile
# 可与俄/英/乌并存：只更新 voices/natan 与 languages/Polish，不删除其它语种
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_polish.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_pl_setup'
$VoiceUrls = @(
    'https://github.com/RHVoice/natan-pol/releases/download/v4.10/RHVoice-voice-Polish-Natan-4.10.1011.10.nvda-addon',
    'https://rhvoice.org/download/RHVoice-voice-Polish-Natan-v4.10.zip'
)
$LangUrls = @(
    'https://github.com/RHVoice/Polish/releases/download/1.21/RHVoice-language-Polish-v1.21.zip',
    'https://rhvoice.org/download/RHVoice-language-Polish-v1.13.zip'
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

$voiceZip = Join-Path $Cache 'natan.zip'
$langZip = Join-Path $Cache 'polish-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls $LangUrls -MinBytes 50000

$natanDir = Join-Path $PackVoices 'natan'
if (Test-Path $natanDir) { Remove-Item -Recurse -Force $natanDir }
New-Item -ItemType Directory -Path $natanDir -Force | Out-Null
Write-Host 'Extract voice natan ...' -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $natanDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $natanDir
}

$plLangDir = Join-Path $PackLangs 'Polish'
if (Test-Path $plLangDir) { Remove-Item -Recurse -Force $plLangDir }
New-Item -ItemType Directory -Path $plLangDir -Force | Out-Null
Write-Host 'Extract language Polish ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $plLangDir

if (-not (Test-Path (Join-Path $natanDir 'voice.info'))) {
    throw 'Missing voices/natan/voice.info after extract'
}
if (-not (Test-Path (Join-Path $plLangDir 'language.info'))) {
    throw 'Missing languages/Polish/language.info after extract'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Polish RHVoice (natan) packed. Clean + Rebuild HAP, reinstall app, install Polish in TTS voice screen.' -ForegroundColor Green
