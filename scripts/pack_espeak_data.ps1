# 打包 espeak-ng 词典到 resfile/espeakdata.zip（Piper espeak 语音合成必需）
# zip 内路径: espeak-ng-data/*（解压到 filesDir/silero_tts/ 后与 SileroModelPaths 一致）
# 用法: .\scripts\pack_espeak_data.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ResDir = Join-Path $Root 'entry\src\main\resources\resfile'
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'
$ZipOut = Join-Path $ResDir 'espeakdata.zip'
$ZipRaw = Join-Path $RawDir 'espeakdata.zip'

$candidates = @(
    (Join-Path $Root 'Mencaje.translator\espeakng\prebuilt\espeak-ng-data'),
    (Join-Path $Root 'third_party\espeak-ng\espeak-ng-data')
)
$DataSrc = ''
foreach ($c in $candidates) {
    $marker = Join-Path $c 'en_dict'
    if ((Test-Path $marker) -and ((Get-Item $marker).Length -ge 1024)) {
        $DataSrc = $c
        break
    }
}
if ($DataSrc.Length -eq 0) {
    throw "espeak-ng-data not found — expected en_dict under one of: $($candidates -join ', ')"
}

New-Item -ItemType Directory -Force -Path $ResDir | Out-Null
if (Test-Path $ZipOut) { Remove-Item -Force $ZipOut }

python -c @"
import zipfile, os
src = r'$DataSrc'
zip_path = r'$ZipOut'
arc_prefix = 'espeak-ng-data'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            arc = os.path.join(arc_prefix, os.path.relpath(full, src))
            zf.write(full, arc.replace('\\\\', '/'))
print('packed', zip_path, os.path.getsize(zip_path))
"@
if ($LASTEXITCODE -ne 0) { throw 'espeakdata.zip pack failed' }

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
Copy-Item -Force $ZipOut $ZipRaw
$mb = [math]::Round((Get-Item $ZipOut).Length / 1MB, 1)
Write-Host "Packed espeak-ng-data -> $ZipOut ($mb MB)" -ForegroundColor Green
Write-Host "Copied -> $ZipRaw (rawfile fallback for getRawFd)" -ForegroundColor Green
Write-Host "DevEco Clean + Rebuild HAP; reinstall app before testing Piper espeak voices (e.g. ar)."
