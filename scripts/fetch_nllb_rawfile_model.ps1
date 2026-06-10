# 下载 NLLB CT2 模型 → rawfile/nllb200_distilled_600m.zip（编入 HAP，首启 zlib 解压到 filesDir）
# 默认不把 2.4GB 明文放进 resfile，避免 HAP>4GB / zip64 签名失败。
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\fetch_nllb_rawfile_model.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\fetch_nllb_rawfile_model.ps1 -IncludeResfile

param(
    [string]$Repo = 'entai2965/nllb-200-distilled-600M-ctranslate2',
    [string]$MirrorBase = 'https://hf-mirror.com',
    [switch]$IncludeResfile
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RawfileDir = Join-Path $Root 'entry\src\main\resources\rawfile'
$ResfileDir = Join-Path $Root 'entry\src\main\resources\resfile'
$BundleDir = Join-Path $ResfileDir 'nllb-200-distilled-600M'
$CacheDir = Join-Path $Root 'third_party\models\nllb-ct2-download'
$FolderName = 'nllb-200-distilled-600M'
$StageDir = Join-Path $CacheDir $FolderName
$ZipInRaw = Join-Path $RawfileDir 'nllb200_distilled_600m.zip'
$ZipInCache = Join-Path $CacheDir 'nllb200_distilled_600m.zip'
$ZipMinBytes = 80MB

New-Item -ItemType Directory -Path $RawfileDir -Force | Out-Null
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

function Get-ModelSourceDir {
    $stash = Join-Path $Root 'third_party\models\nllb-resfile-stash\nllb-200-distilled-600M'
    if ((Test-Path (Join-Path $stash 'model.bin')) -and ((Get-Item (Join-Path $stash 'model.bin')).Length -gt 50000000)) {
        return $stash
    }
    if ((Test-Path (Join-Path $StageDir 'model.bin')) -and ((Get-Item (Join-Path $StageDir 'model.bin')).Length -gt 50000000)) {
        return $StageDir
    }
    if ((Test-Path (Join-Path $BundleDir 'model.bin')) -and ((Get-Item (Join-Path $BundleDir 'model.bin')).Length -gt 50000000)) {
        return $BundleDir
    }
    return $null
}

function Get-MirrorUrl {
    param([string]$FileName)
    return "$MirrorBase/$Repo/resolve/main/$FileName"
}

function Download-File {
    param([string]$FileName, [long]$MinBytes = 1024)
    $dest = Join-Path $StageDir $FileName
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -ge $MinBytes)) {
        Write-Host "  [skip] $FileName ($([math]::Round((Get-Item $dest).Length/1MB, 1)) MB)" -ForegroundColor DarkGray
        return
    }
    $url = Get-MirrorUrl $FileName
    Write-Host "  [get] $url" -ForegroundColor Yellow
    $tmp = "$dest.part"
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -fL --retry 5 --retry-delay 3 -o $tmp $url
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path $tmp) { Remove-Item -Force $tmp }
            throw "curl failed for $FileName exit=$LASTEXITCODE"
        }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -MaximumRedirection 20
    }
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt $MinBytes) {
        if (Test-Path $tmp) { Remove-Item -Force $tmp }
        throw "Download too small: $FileName"
    }
    Move-Item -Force $tmp $dest
    Write-Host "  [ok] $FileName ($([math]::Round((Get-Item $dest).Length/1MB, 1)) MB)" -ForegroundColor Green
}

function New-NllbZip {
    param([string]$SourceDir, [string]$OutZip)
    if (Test-Path $OutZip) { Remove-Item -Force $OutZip }
    Write-Host "Create zip (compresslevel=1, fast) ..." -ForegroundColor Cyan
    $pyZip = @"
import zipfile, os
root = r'$SourceDir'
out = r'$OutZip'
prefix = '$FolderName'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as zf:
    for name in ('config.json', 'shared_vocabulary.json', 'sentencepiece.bpe.model', 'model.bin'):
        full = os.path.join(root, name)
        if not os.path.isfile(full):
            raise SystemExit('missing ' + full)
        arc = prefix + '/' + name
        zf.write(full, arc)
print('zip ok', out, os.path.getsize(out))
"@
    $tmpZip = Join-Path $env:TEMP 'pack_nllb_zip.py'
    Set-Content -Path $tmpZip -Value $pyZip -Encoding UTF8
    python $tmpZip
    if (-not (Test-Path $OutZip) -or (Get-Item $OutZip).Length -lt $ZipMinBytes) {
        throw "Zip too small or missing: $OutZip"
    }
}

$srcDir = Get-ModelSourceDir
if ($null -eq $srcDir) {
    Write-Host "Mirror: $MirrorBase  Repo: $Repo" -ForegroundColor Cyan
    Download-File 'config.json' 100
    Download-File 'shared_vocabulary.json' 10000
    Download-File 'sentencepiece.bpe.model' 100000
    Download-File 'model.bin' 50000000
    $srcDir = $StageDir
} else {
    Write-Host "[skip] model files present at: $srcDir" -ForegroundColor Green
}

if ($IncludeResfile) {
    if (Test-Path $BundleDir) { Remove-Item -Recurse -Force $BundleDir }
    Write-Host "Copy to resfile (large HAP, dev only) ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
    Copy-Item -Path (Join-Path $srcDir '*') -Destination $BundleDir -Recurse -Force
    $hfMeta = Join-Path $BundleDir 'huggingface'
    if (Test-Path $hfMeta) { Remove-Item -Recurse -Force $hfMeta }
    $hfCache = Join-Path $BundleDir '.cache'
    if (Test-Path $hfCache) { Remove-Item -Recurse -Force $hfCache }
}

if ((Test-Path $ZipInRaw) -and ((Get-Item $ZipInRaw).Length -ge $ZipMinBytes)) {
    Write-Host "[skip] rawfile zip already present: $ZipInRaw" -ForegroundColor Green
} else {
    New-NllbZip -SourceDir $srcDir -OutZip $ZipInCache
    Copy-Item -Force $ZipInCache $ZipInRaw
    Write-Host "[ok] rawfile zip: $ZipInRaw ($([math]::Round((Get-Item $ZipInRaw).Length/1MB, 1)) MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next: DevEco Clean + Rebuild, uninstall old app, reinstall HAP." -ForegroundColor Cyan
Write-Host "First launch auto-extracts zip to files/models/ (no Settings download)." -ForegroundColor Cyan
if (-not $IncludeResfile) {
    Write-Host "HAP uses compressed NLLB zip (~1.5GB) instead of ~2.4GB resfile folder." -ForegroundColor DarkGray
}
