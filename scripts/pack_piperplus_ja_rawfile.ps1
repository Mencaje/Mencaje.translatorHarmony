# 打包 piper-plus 日语语音到 rawfile（ONNX ~38MB + OpenJTalk 词典 ~20MB）
# 用法: .\scripts\pack_piperplus_ja_rawfile.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Work = Join-Path $Root 'third_party\ohos\piperplus_pack_work'
$Bundle = Join-Path $Work 'piper-plus-ja'
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'
$ResDir = Join-Path $Root 'entry\src\main\resources\resfile'
$ZipOut = Join-Path $RawDir 'piperplus_ja_voice.zip'
$ZipRes = Join-Path $ResDir 'piperplus_ja_voice.zip'

$OnnxUrl = 'https://huggingface.co/ayousanz/piper-plus-tsukuyomi-chan/resolve/main/tsukuyomi-chan-6lang-fp16.onnx'
$CfgUrl = 'https://huggingface.co/ayousanz/piper-plus-tsukuyomi-chan/raw/main/config.json'
$DictUrl = 'https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz'

function Invoke-Download([string]$Url, [string]$OutFile, [int]$MinBytes = 100000) {
    if (Test-Path $OutFile) {
        if ((Get-Item $OutFile).Length -ge $MinBytes) { return }
    }
    $candidates = @($Url)
    if ($Url -match '^https://github\.com/') {
        $candidates += "https://ghproxy.net/$Url", "https://mirror.ghproxy.com/$Url"
    }
    if ($Url -match 'huggingface\.co') {
        $candidates += $Url -replace 'huggingface\.co', 'hf-mirror.com'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
    foreach ($u in $candidates) {
        Write-Host "[download] $u"
        try {
            curl.exe -L --connect-timeout 30 --max-time 7200 -o $OutFile $u 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
                return
            }
        } catch { }
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        try {
            Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing
            if ((Get-Item $OutFile).Length -ge $MinBytes) { return }
        } catch {
            Write-Host "[warn] failed: $u" -ForegroundColor Yellow
        }
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
    }
    throw "Download failed: $Url"
}

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Bundle | Out-Null

$onnx = Join-Path $Bundle 'tsukuyomi-chan-6lang-fp16.onnx'
$cfg = Join-Path $Bundle 'config.json'
Invoke-Download $OnnxUrl $onnx -MinBytes 8000000
Invoke-Download $CfgUrl $cfg -MinBytes 512

$sanitize = Join-Path $Root 'scripts\sanitize_piperplus_ja_config.py'
if (-not (Test-Path $sanitize)) { throw "Missing $sanitize" }
Write-Host "[sanitize] phoneme_id_map PUA fix for C++ piper"
python $sanitize $cfg
if ($LASTEXITCODE -ne 0) { throw "sanitize_piperplus_ja_config failed" }

$dictTar = Join-Path $Work 'open_jtalk_dic.tar.gz'
Invoke-Download $DictUrl $dictTar
python -c @"
import tarfile, os, shutil
tar_path = r'$dictTar'
bundle = r'$Bundle'
dict_dst = os.path.join(bundle, 'open_jtalk_dic')
with tarfile.open(tar_path, 'r:gz') as t:
    t.extractall(bundle)
# tarball expands to open_jtalk_dic_utf_8-1.11/
for name in os.listdir(bundle):
    p = os.path.join(bundle, name)
    if os.path.isdir(p) and name.startswith('open_jtalk_dic'):
        if os.path.isdir(dict_dst):
            shutil.rmtree(dict_dst)
        os.rename(p, dict_dst)
        break
if not os.path.isfile(os.path.join(dict_dst, 'sys.dic')):
    raise SystemExit('open_jtalk_dic missing sys.dic')
print('dict ok', dict_dst)
"@

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
if (Test-Path $ZipOut) { Remove-Item -Force $ZipOut }
python -c @"
import zipfile, os
bundle = r'$Bundle'
zip_path = r'$ZipOut'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(bundle):
        for f in files:
            full = os.path.join(root, f)
            arc = os.path.join('piper-plus-ja', os.path.relpath(full, bundle))
            zf.write(full, arc)
print('zip', zip_path, os.path.getsize(zip_path))
"@
New-Item -ItemType Directory -Force -Path $ResDir | Out-Null
Copy-Item -Force $ZipOut $ZipRes
Remove-Item -Force $ZipOut -ErrorAction SilentlyContinue
$mb = [math]::Round((Get-Item $ZipRes).Length / 1MB, 1)
Write-Host "Packed Japanese piper-plus -> resfile only ($mb MB); rawfile copy omitted to save HAP size"
Write-Host "Then DevEco Clean + Rebuild HAP, uninstall app, reinstall, install Japanese in app."
