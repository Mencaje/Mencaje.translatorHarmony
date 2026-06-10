# 下载并布置俄语 RHVoice 数据（声线 aleksandr + Russian 语言包），并打包 rawfile/rhvoice_voices.zip
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_russian.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_ru_setup'
$VoiceUrl = 'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-voice-Russian-Aleksandr-4.2.2010.9.nvda-addon'
$LangUrl = 'https://rhvoice.org/download/RHVoice-language-Russian-v2.10.zip'

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
    param([string]$OutFile, [string]$Url, [long]$MinBytes = 50000)
    if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
        Write-Host "OK (cached): $OutFile" -ForegroundColor Green
        return
    }
    Write-Host "Downloading $Url ..." -ForegroundColor Cyan
    $tmp = "$OutFile.part"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    curl.exe -L --retry 3 --connect-timeout 60 -o $tmp $Url
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt $MinBytes) {
        throw "Download failed or too small: $Url"
    }
    Move-Item -Force $tmp $OutFile
    Write-Host "Saved $OutFile ($((Get-Item $OutFile).Length) bytes)" -ForegroundColor Green
}

if (Test-Path $Cache) { Remove-Item -Recurse -Force $Cache }
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
New-Item -ItemType Directory -Path $PackVoices -Force | Out-Null
New-Item -ItemType Directory -Path $PackLangs -Force | Out-Null

$voiceZip = Join-Path $Cache 'aleksandr.nvda-addon'
$langZip = Join-Path $Cache 'russian-lang.zip'
Get-Archive -OutFile $voiceZip -Url $VoiceUrl -MinBytes 1000000
Get-Archive -OutFile $langZip -Url $LangUrl -MinBytes 100000

$aleksandrDir = Join-Path $PackVoices 'aleksandr'
if (Test-Path $aleksandrDir) { Remove-Item -Recurse -Force $aleksandrDir }
New-Item -ItemType Directory -Path $aleksandrDir -Force | Out-Null
Write-Host 'Extract voice aleksandr ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $aleksandrDir -Prefix 'data/'

$ruLangDir = Join-Path $PackLangs 'Russian'
if (Test-Path $ruLangDir) { Remove-Item -Recurse -Force $ruLangDir }
New-Item -ItemType Directory -Path $ruLangDir -Force | Out-Null
Write-Host 'Extract language Russian ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $ruLangDir

if (-not (Test-Path (Join-Path $aleksandrDir 'voice.info'))) {
    throw 'Missing voices/aleksandr/voice.info after extract'
}
if (-not (Test-Path (Join-Path $ruLangDir 'language.info'))) {
    throw 'Missing languages/Russian/language.info after extract'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Russian RHVoice pack ready. Clean + Rebuild HAP, then install Russian in TTS voice screen.' -ForegroundColor Green
