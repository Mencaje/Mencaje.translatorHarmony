# 下载巴西葡萄牙语 RHVoice（声线 Leticia-F123 + Brazilian-Portuguese 语言包），合并 pack/ 并打包 rawfile
# 可与俄/英/乌/波/西等并存：只更新 voices/Leticia-F123 与 languages/Brazilian-Portuguese
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_brazilian_portuguese.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_pt_setup'
$VoiceProfileDir = 'Leticia-F123'
$VoiceUrls = @(
    'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-Brazilian-Portuguese-voice-Leticia-F123-4.6.1019.9.nvda-addon',
    'https://rhvoice.org/download/RHVoice-Brazilian-Portuguese-voice-Leticia-F123-v4.6.zip'
)
$LangUrls = @(
    'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-F123-Brazilian-Portuguese-language-v1.19.zip',
    'https://rhvoice.org/download/RHVoice-F123-Brazilian-Portuguese-language-v1.19.zip',
    'https://rhvoice.org/download//RHVoice-F123-Brazilian-Portuguese-language-v1.19.zip',
    'https://github.com/RHVoice/Brazilian-Portuguese/releases/download/1.24/RHVoice-F123-Brazilian-Portuguese-language-v1.24.zip',
    'https://github.com/RHVoice/Brazilian-Portuguese/releases/download/1.23/RHVoice-F123-Brazilian-Portuguese-language-v1.23.zip'
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

$voiceZip = Join-Path $Cache 'leticia.zip'
$langZip = Join-Path $Cache 'pt-br-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls $LangUrls -MinBytes 50000

$voiceDir = Join-Path $PackVoices $VoiceProfileDir
if (Test-Path $voiceDir) { Remove-Item -Recurse -Force $voiceDir }
New-Item -ItemType Directory -Path $voiceDir -Force | Out-Null
Write-Host "Extract voice $VoiceProfileDir ..." -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $voiceDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $voiceDir
}

$ptLangDir = Join-Path $PackLangs 'Brazilian-Portuguese'
if (Test-Path $ptLangDir) { Remove-Item -Recurse -Force $ptLangDir }
New-Item -ItemType Directory -Path $ptLangDir -Force | Out-Null
Write-Host 'Extract language Brazilian-Portuguese ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $ptLangDir

if (-not (Test-Path (Join-Path $voiceDir 'voice.info'))) {
    throw "Missing voices/$VoiceProfileDir/voice.info after extract"
}
if (-not (Test-Path (Join-Path $ptLangDir 'language.info'))) {
    throw 'Missing languages/Brazilian-Portuguese/language.info after extract'
}
$tokFst = Join-Path $ptLangDir 'tok.fst'
$g2pFst = Join-Path $ptLangDir 'g2p.fst'
if (-not ((Test-Path $tokFst) -and (Get-Item $tokFst).Length -ge 1000)) {
    throw 'Missing languages/Brazilian-Portuguese/tok.fst — language zip incomplete; re-download lang zip'
}
if (-not ((Test-Path $g2pFst) -and (Get-Item $g2pFst).Length -ge 1000)) {
    throw 'Missing languages/Brazilian-Portuguese/g2p.fst — language zip incomplete; re-download lang zip'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Brazilian Portuguese RHVoice (Leticia-F123) packed. Clean + Rebuild HAP, reinstall, install pt in TTS voice screen.' -ForegroundColor Green
