# 下载格鲁吉亚语 RHVoice（声线 natia + Georgian 语言包），合并到 pack/ 并打包 rawfile
# 可与俄/英/乌/波/西/葡等并存：只更新 voices/natia 与 languages/Georgian
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_georgian.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_ka_setup'
$VoiceUrls = @(
    'https://github.com/RHVoice/natia-kat/releases/download/4.0/RHVoice-voice-Georgian-Natia-4.0.1016.12.nvda-addon',
    'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-voice-Georgian-Natia-4.0.1012.9.nvda-addon',
    'https://rhvoice.org/download/RHVoice-voice-Georgian-Natia-v4.0.zip'
)
$LangUrls = @(
    'https://rhvoice.org/download/RHVoice-language-Georgian-v1.12.zip'
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

function Test-LanguageDataReady {
    param([string]$LangDir)
    if (-not (Test-Path (Join-Path $LangDir 'language.info'))) {
        return $false
    }
    $graphTxt = Join-Path $LangDir 'graph.txt'
    $tokFst = Join-Path $LangDir 'tok.fst'
    $cmulexFst = Join-Path $LangDir 'cmulex.fst'
    $g2pFst = Join-Path $LangDir 'g2p.fst'
    if ((Test-Path $graphTxt) -and (Get-Item $graphTxt).Length -ge 64) { return $true }
    if ((Test-Path $tokFst) -and (Get-Item $tokFst).Length -ge 1000) {
        if ((Test-Path $g2pFst) -and (Get-Item $g2pFst).Length -ge 1000) { return $true }
        if ((Test-Path $cmulexFst) -and (Get-Item $cmulexFst).Length -ge 1000) { return $true }
    }
    return $false
}

if (Test-Path $Cache) { Remove-Item -Recurse -Force $Cache }
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
New-Item -ItemType Directory -Path $PackVoices -Force | Out-Null
New-Item -ItemType Directory -Path $PackLangs -Force | Out-Null

$voiceZip = Join-Path $Cache 'natia.zip'
$langZip = Join-Path $Cache 'georgian-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls $LangUrls -MinBytes 20000

$natiaDir = Join-Path $PackVoices 'natia'
if (Test-Path $natiaDir) { Remove-Item -Recurse -Force $natiaDir }
New-Item -ItemType Directory -Path $natiaDir -Force | Out-Null
Write-Host 'Extract voice natia ...' -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $natiaDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $natiaDir
}

$kaLangDir = Join-Path $PackLangs 'Georgian'
if (Test-Path $kaLangDir) { Remove-Item -Recurse -Force $kaLangDir }
New-Item -ItemType Directory -Path $kaLangDir -Force | Out-Null
Write-Host 'Extract language Georgian ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $kaLangDir

if (-not (Test-Path (Join-Path $natiaDir 'voice.info'))) {
    throw 'Missing voices/natia/voice.info after extract'
}
if (-not (Test-LanguageDataReady -LangDir $kaLangDir)) {
    throw 'Georgian language data incomplete (need graph.txt or tok.fst+cmulex/g2p.fst)'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Georgian RHVoice (natia) packed. Clean + Rebuild HAP, reinstall app, install Georgian in TTS voice screen.' -ForegroundColor Green
