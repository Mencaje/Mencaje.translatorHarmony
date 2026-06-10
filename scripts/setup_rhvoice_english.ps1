# 下载英语 RHVoice（声线 bdl + English 语言包），合并到 third_party/rhvoice/pack/ 并打包 rawfile
# 可与俄语并存：若已运行 setup_rhvoice_russian.ps1，本脚本只追加 bdl，不删除 aleksandr
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_english.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$PackVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$PackLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$Cache = Join-Path $env:TEMP 'rhvoice_en_setup'
$VoiceUrl = 'https://rhvoice.eu-central-1.linodeobjects.com/RHVoice-voice-English-Bdl-4.1.2008.9.nvda-addon'
$LangUrl = 'https://rhvoice.org/download/RHVoice-language-English-v2.8.zip'

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

$voiceZip = Join-Path $Cache 'bdl.nvda-addon'
$langZip = Join-Path $Cache 'english-lang.zip'
Get-Archive -OutFile $voiceZip -Url $VoiceUrl -MinBytes 500000
Get-Archive -OutFile $langZip -Url $LangUrl -MinBytes 50000

$bdlDir = Join-Path $PackVoices 'bdl'
if (Test-Path $bdlDir) { Remove-Item -Recurse -Force $bdlDir }
New-Item -ItemType Directory -Path $bdlDir -Force | Out-Null
Write-Host 'Extract voice bdl ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $voiceZip -DestDir $bdlDir -Prefix 'data/'

$enLangDir = Join-Path $PackLangs 'English'
if (Test-Path $enLangDir) { Remove-Item -Recurse -Force $enLangDir }
New-Item -ItemType Directory -Path $enLangDir -Force | Out-Null
Write-Host 'Extract language English ...' -ForegroundColor Cyan
Expand-ZipEntryPrefix -ZipPath $langZip -DestDir $enLangDir

if (-not (Test-Path (Join-Path $bdlDir 'voice.info'))) {
    throw 'Missing voices/bdl/voice.info after extract'
}
if (-not (Test-Path (Join-Path $enLangDir 'language.info'))) {
    throw 'Missing languages/English/language.info after extract'
}
$graphTxt = Join-Path $enLangDir 'graph.txt'
$tokFst = Join-Path $enLangDir 'tok.fst'
$cmulexFst = Join-Path $enLangDir 'cmulex.fst'
$g2pFst = Join-Path $enLangDir 'g2p.fst'
$langOk = $false
if ((Test-Path $graphTxt) -and (Get-Item $graphTxt).Length -ge 64) { $langOk = $true }
if ((Test-Path $tokFst) -and (Get-Item $tokFst).Length -ge 1000) {
    if ((Test-Path $g2pFst) -and (Get-Item $g2pFst).Length -ge 1000) { $langOk = $true }
    if ((Test-Path $cmulexFst) -and (Get-Item $cmulexFst).Length -ge 1000) { $langOk = $true }
}
if (-not $langOk) {
    throw 'English language data incomplete (need graph.txt or tok.fst+cmulex.fst or tok.fst+g2p.fst)'
}

$packScript = Join-Path $Root 'scripts\pack_rhvoice_voices.ps1'
if (-not (Test-Path $packScript)) {
    throw "Missing $packScript"
}
& $packScript

Write-Host ''
Write-Host '[ok] English RHVoice (bdl) packed. Clean + Rebuild HAP, reinstall app, install English in TTS voice screen.' -ForegroundColor Green
