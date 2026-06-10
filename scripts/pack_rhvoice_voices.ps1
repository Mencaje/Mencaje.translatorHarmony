# 打包 RHVoice 语音数据为 rawfile/rhvoice_voices.zip
# zip 根目录须含 voices/ 与 languages/（解压到 filesDir/silero_tts/rhvoice/）
# 须用正斜杠路径打包（勿用 Compress-Archive，HarmonyOS zlib 解压后无法识别 voices\）
# 俄语一键准备: scripts\setup_rhvoice_russian.ps1
#
# 用法：
#   1. 从 https://github.com/RHVoice/RHVoice/releases 下载语音数据（或本机 RHVoice 安装目录下的 share）
#   2. 将 voices 目录放到 third_party\rhvoice\pack\voices\
#   3. powershell -ExecutionPolicy Bypass -File scripts\pack_rhvoice_voices.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SrcVoices = Join-Path $Root 'third_party\rhvoice\pack\voices'
$SrcLangs = Join-Path $Root 'third_party\rhvoice\pack\languages'
$OutZip = Join-Path $Root 'entry\src\main\resources\rawfile\rhvoice_voices.zip'
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'

if (-not (Test-Path $SrcVoices)) {
    Write-Host "[!] Missing $SrcVoices" -ForegroundColor Yellow
    Write-Host "    Run: scripts\setup_rhvoice_russian.ps1  (俄语 aleksandr + Russian 语言包)" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path (Split-Path $SrcVoices) -Force | Out-Null
    exit 1
}

$voiceDirs = @(Get-ChildItem -Path $SrcVoices -Directory -ErrorAction SilentlyContinue)
if ($voiceDirs.Count -eq 0) {
    Write-Host "[!] No voices under $SrcVoices" -ForegroundColor Yellow
    Write-Host "    Run: setup_rhvoice_russian.ps1 / setup_rhvoice_english.ps1 / setup_rhvoice_ukrainian.ps1 / setup_rhvoice_polish.ps1 / setup_rhvoice_spanish.ps1 / setup_rhvoice_brazilian_portuguese.ps1 / setup_rhvoice_georgian.ps1 / setup_rhvoice_kyrgyz.ps1 / setup_rhvoice_tatar.ps1 / setup_rhvoice_macedonian.ps1 / setup_rhvoice_albanian.ps1 / setup_rhvoice_esperanto.ps1" -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
$Staging = Join-Path $env:TEMP "rhvoice_pack_staging"
if (Test-Path $Staging) { Remove-Item -Recurse -Force $Staging }
New-Item -ItemType Directory -Path (Join-Path $Staging 'voices') -Force | Out-Null
Copy-Item -Recurse (Join-Path $SrcVoices '*') (Join-Path $Staging 'voices') -Force
if (Test-Path $SrcLangs) {
    New-Item -ItemType Directory -Path (Join-Path $Staging 'languages') -Force | Out-Null
    Copy-Item -Recurse (Join-Path $SrcLangs '*') (Join-Path $Staging 'languages') -Force
}

if (Test-Path $OutZip) { Remove-Item -Force $OutZip }

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Write-Host "[!] python not found — install Python 3 or use DevEco bundled python for zip packing" -ForegroundColor Red
    exit 1
}

python -c @"
import zipfile, os
staging = r'$Staging'
zip_path = r'$OutZip'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(staging):
        for f in files:
            full = os.path.join(root, f)
            arc = os.path.relpath(full, staging).replace(chr(92), '/')
            zf.write(full, arc)
print('zip', zip_path, os.path.getsize(zip_path))
"@

Remove-Item -Recurse -Force $Staging

# 校验 zip 内路径为正斜杠，且每个 pack 声线均有 voice.info
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($OutZip)
$packedProfiles = @()
foreach ($e in $z.Entries) {
    if ($e.FullName -match '\\') {
        $z.Dispose()
        throw "Zip entry uses backslash: $($e.FullName) — repack failed"
    }
}
$z.Dispose()
foreach ($vd in $voiceDirs) {
    $profile = $vd.Name
    $need = "voices/$profile/voice.info"
    $z2 = [System.IO.Compression.ZipFile]::OpenRead($OutZip)
    $found = $false
    foreach ($e in $z2.Entries) {
        if ($e.FullName -eq $need) { $found = $true; break }
    }
    $z2.Dispose()
    if (-not $found) {
        throw "Zip missing $need"
    }
    $packedProfiles += $profile
}

$mb = [math]::Round((Get-Item $OutZip).Length / 1MB, 1)
Write-Host "[ok] $OutZip ($mb MB) voices: $($packedProfiles -join ', ')"
