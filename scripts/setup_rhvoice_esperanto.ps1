# 下载世界语 RHVoice（声线 Spomenka + Esperanto 语言包），合并 pack/ 并打包 rawfile
# 可与俄/英/阿尔巴尼亚等并存：只更新 voices/spomenka 与 languages/Esperanto
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_esperanto.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_eo_setup'
$VoiceUrls = @(
    'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-voice-Esperanto-Spomenka-4.0.1002.9.nvda-addon',
    'https://rhvoice.org/download/RHVoice-voice-Esperanto-Spomenka-v4.0.zip',
    'https://github.com/RHVoice/spomenka-epo/releases/download/4.2/RHVoice-voice-Esperanto-Spomenka-4.2.1003.12.nvda-addon'
)
# v1.2 on rhvoice.org 仅含元数据；合成需要 v1.3 的 g2p.fst / tok.fst 等
$LangUrls = @(
    'https://github.com/RHVoice/Esperanto/releases/download/1.3/RHVoice-language-Esperanto-v1.3.zip'
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

function Test-ZipArchive {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $ok = $zip.Entries.Count -gt 0
        $zip.Dispose()
        return $ok
    } catch {
        return $false
    }
}

function Get-Archive {
    param([string]$OutFile, [string[]]$Urls, [long]$MinBytes = 50000)
    $needG2p = $OutFile -like '*esperanto-lang*'
    if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
        $zipOk = if ($needG2p) { Test-LangZipHasG2p $OutFile } else { Test-ZipArchive $OutFile }
        if ($zipOk) {
            Write-Host "OK (cached): $OutFile" -ForegroundColor Green
            return
        }
        Remove-Item -Force $OutFile
    }
    $lastErr = $null
    foreach ($Url in $Urls) {
        Write-Host "Downloading $Url ..." -ForegroundColor Cyan
        $tmp = "$OutFile.part"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        curl.exe -fL --retry 3 --connect-timeout 90 -o $tmp $Url
        $zipOk = if ($needG2p) { Test-LangZipHasG2p $tmp } else { Test-ZipArchive $tmp }
        if ((Test-Path $tmp) -and (Get-Item $tmp).Length -ge $MinBytes -and $zipOk) {
            Move-Item -Force $tmp $OutFile
            Write-Host "Saved $OutFile ($((Get-Item $OutFile).Length) bytes)" -ForegroundColor Green
            return
        }
        $lastErr = $Url
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
    throw "Download failed or invalid zip: $lastErr"
}

function Test-LangZipHasG2p {
    param([string]$ZipPath)
    if (-not (Test-ZipArchive $ZipPath)) { return $false }
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $hasG2p = $false
        foreach ($e in $zip.Entries) {
            if ($e.FullName -eq 'g2p.fst') { $hasG2p = $true; break }
        }
        $zip.Dispose()
        return $hasG2p
    } catch {
        return $false
    }
}

function Expand-LanguageZip {
    param(
        [string]$ZipPath,
        [string]$DestDir
    )
    if (Test-Path $DestDir) { Remove-Item -Recurse -Force $DestDir }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' $ZipPath $DestDir
        if ($LASTEXITCODE -ne 0) {
            throw "python extract failed for $ZipPath"
        }
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestDir)
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
        if ((Test-Path $g2pFst) -and (Get-Item $g2pFst).Length -ge 64) { return $true }
        if ((Test-Path $cmulexFst) -and (Get-Item $cmulexFst).Length -ge 1000) { return $true }
    }
    return $false
}

if (-not (Test-Path $Cache)) {
    New-Item -ItemType Directory -Path $Cache -Force | Out-Null
}
New-Item -ItemType Directory -Path $PackVoices -Force | Out-Null
New-Item -ItemType Directory -Path $PackLangs -Force | Out-Null

$voiceZip = Join-Path $Cache 'spomenka.zip'
$langZip = Join-Path $Cache 'esperanto-lang.zip'
Get-Archive -OutFile $voiceZip -Urls $VoiceUrls -MinBytes 500000
Get-Archive -OutFile $langZip -Urls $LangUrls -MinBytes 5000

$spomenkaDir = Join-Path $PackVoices 'spomenka'
if (Test-Path $spomenkaDir) { Remove-Item -Recurse -Force $spomenkaDir }
New-Item -ItemType Directory -Path $spomenkaDir -Force | Out-Null
Write-Host 'Extract voice spomenka ...' -ForegroundColor Cyan
$voicePrefix = 'data/'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$vz = [System.IO.Compression.ZipFile]::OpenRead($voiceZip)
$hasDataPrefix = $false
foreach ($e in $vz.Entries) {
    if ($e.FullName.StartsWith('data/')) { $hasDataPrefix = $true; break }
}
$vz.Dispose()
if ($hasDataPrefix) {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $spomenkaDir -Prefix $voicePrefix
} else {
    Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $spomenkaDir
}

$eoLangDir = Join-Path $PackLangs 'Esperanto'
Write-Host 'Extract language Esperanto ...' -ForegroundColor Cyan
Expand-LanguageZip -ZipPath $langZip -DestDir $eoLangDir

if (-not (Test-Path (Join-Path $spomenkaDir 'voice.info'))) {
    throw 'Missing voices/spomenka/voice.info after extract'
}
if (-not (Test-LanguageDataReady -LangDir $eoLangDir)) {
    throw 'Esperanto language data incomplete (need graph.txt or tok.fst+g2p/cmulex)'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] Esperanto RHVoice (Spomenka) packed. Clean + Rebuild HAP, reinstall, install eo in TTS voice screen.' -ForegroundColor Green
