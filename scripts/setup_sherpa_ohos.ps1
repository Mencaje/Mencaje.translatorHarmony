# 从 sherpa_onnx HAR 提取鸿蒙 arm64 推理库，并可选打包英语 Piper 语音 zip 到 rawfile。
# 用法：.\scripts\setup_sherpa_ohos.ps1
#       .\scripts\setup_sherpa_ohos.ps1 -PackEnVoice   # 额外生成 ~65MB sherpa_en_vits.zip
#       .\scripts\setup_sherpa_ohos.ps1 -PackFrVoice   # 额外生成 ~26MB sherpa_fr_vits.zip（法语 Piper）
#       .\scripts\setup_sherpa_ohos.ps1 -PackDeVoice   # 额外生成 ~65MB sherpa_de_vits.zip（德语 Piper）
#       .\scripts\setup_sherpa_ohos.ps1 -PackEsVoice   # 额外生成 ~26MB sherpa_es_vits.zip（西班牙语 Piper）
#       .\scripts\setup_sherpa_ohos.ps1 -PackRuVoice   # 额外生成 ~65MB sherpa_ru_vits.zip（俄语 Piper）

param(
    [switch]$PackEnVoice,
    [switch]$PackFrVoice,
    [switch]$PackDeVoice,
    [switch]$PackEsVoice,
    [switch]$PackRuVoice
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SherpaDir = Join-Path $Root 'third_party\ohos\sherpa'
$HarPath = Join-Path $SherpaDir 'sherpa_onnx-v1.12.6.har'
$HarUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.6/sherpa_onnx-v1.12.6.har'
$HeadersTar = Join-Path $SherpaDir 'sherpa-onnx-v1.12.6-ohos-arm64-v8a.tar.bz2'
$HeadersUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.6/sherpa-onnx-v1.12.6-ohos-arm64-v8a.tar.bz2'
# entry/libs/<abi> 才会被 ProcessLibs 打进 HAP（非 src/main/libs）
$LibDstArm = Join-Path $Root 'entry\libs\arm64-v8a'
$LibDstX86 = Join-Path $Root 'entry\libs\x86_64'
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'

if (-not (Test-Path $SherpaDir)) { New-Item -ItemType Directory -Path $SherpaDir -Force | Out-Null }
if (-not (Test-Path $HarPath)) {
    Write-Host "[download] $HarUrl"
    Invoke-WebRequest -Uri $HarUrl -OutFile $HarPath -UseBasicParsing
}
if (-not (Test-Path (Join-Path $SherpaDir 'har_extract\package\libs\arm64-v8a\libsherpa-onnx-c-api.so'))) {
    python -c @"
import tarfile, os, shutil
har = r'$HarPath'
dest = r'$(Join-Path $SherpaDir 'har_extract')'
if os.path.isdir(dest): shutil.rmtree(dest)
os.makedirs(dest, exist_ok=True)
with tarfile.open(har, 'r:gz') as t:
    t.extractall(dest)
print('har ok')
"@
}

if (-not (Test-Path (Join-Path $SherpaDir 'sherpa-onnx-v1.12.6-ohos-arm64-v8a\include\sherpa-onnx\c-api\c-api.h'))) {
    if (-not (Test-Path $HeadersTar)) {
        Write-Host "[download] $HeadersUrl"
        Invoke-WebRequest -Uri $HeadersUrl -OutFile $HeadersTar -UseBasicParsing
    }
    python -c "import tarfile; tarfile.open(r'$HeadersTar','r:bz2').extractall(r'$SherpaDir')"
}

function Copy-SherpaLibsForAbi([string]$AbiFolder, [string]$DestDir) {
    $srcLib = Join-Path $SherpaDir "har_extract\package\libs\$AbiFolder"
    if (-not (Test-Path $srcLib)) {
        Write-Host "[skip] no HAR libs for $AbiFolder" -ForegroundColor Yellow
        return
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    foreach ($name in @('libsherpa-onnx-c-api.so', 'libsherpa_onnx.so', 'libonnxruntime.so', 'libc++_shared.so')) {
        $from = Join-Path $srcLib $name
        if (Test-Path $from) {
            Copy-Item $from (Join-Path $DestDir $name) -Force
            Write-Host "[ok] $name -> $DestDir"
        } else {
            Write-Host "[warn] missing $name in $srcLib" -ForegroundColor Yellow
        }
    }
}

Copy-SherpaLibsForAbi 'arm64-v8a' $LibDstArm
Copy-SherpaLibsForAbi 'x86_64' $LibDstX86

$stamp = Join-Path $SherpaDir 'sherpa_headers_ready.stamp'
Set-Content -Path $stamp -Value "ok $(Get-Date -Format o)" -Encoding ascii
Write-Host "[ok] headers stamp -> $stamp"

function Invoke-SherpaDownload([string]$Url, [string]$OutFile) {
    if (Test-Path $OutFile) { return }
    $candidates = @($Url)
    if ($Url -match '^https://github\.com/') {
        $candidates += @(
            "https://ghproxy.net/$Url",
            "https://mirror.ghproxy.com/$Url"
        )
    }
    foreach ($u in $candidates) {
        Write-Host "[download] $u"
        try {
            curl.exe -L --connect-timeout 30 --max-time 3600 -o $OutFile $u 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 100000) {
                return
            }
        } catch { }
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        try {
            Invoke-WebRequest -Uri $u -OutFile $OutFile -UseBasicParsing
            if ((Get-Item $OutFile).Length -gt 100000) { return }
        } catch {
            Write-Host "[warn] failed: $u" -ForegroundColor Yellow
        }
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
    }
    throw "Download failed for $Url"
}

function Pack-SherpaVoiceZip([string]$TarName, [string]$ModelUrl, [string]$ZipName) {
    $TarModel = Join-Path $SherpaDir $TarName
    if (-not (Test-Path $TarModel)) {
        Invoke-SherpaDownload -Url $ModelUrl -OutFile $TarModel
    }
    $zipOut = Join-Path $RawDir $ZipName
    New-Item -ItemType Directory -Path $RawDir -Force | Out-Null
    python -c @"
import tarfile, zipfile, os, tempfile, shutil
tar_path = r'$TarModel'
zip_path = r'$zipOut'
work = tempfile.mkdtemp()
with tarfile.open(tar_path, 'r:bz2') as t:
    t.extractall(work)
bundle = None
for name in os.listdir(work):
    p = os.path.join(work, name)
    if os.path.isdir(p) and name.startswith('vits-piper'):
        bundle = p
        break
if bundle is None:
    raise SystemExit('bundle dir not found')
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(bundle):
        for f in files:
            full = os.path.join(root, f)
            arc = os.path.relpath(full, work)
            zf.write(full, arc)
shutil.rmtree(work)
print('zip', zip_path, os.path.getsize(zip_path))
"@
    Write-Host "[ok] voice zip -> $zipOut (rebuild HAP)"
}

if ($PackEnVoice) {
    Pack-SherpaVoiceZip `
        'vits-piper-en_US-lessac-low.tar.bz2' `
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-low.tar.bz2' `
        'sherpa_en_vits.zip'
}

if ($PackFrVoice) {
    Pack-SherpaVoiceZip `
        'vits-piper-fr_FR-siwis-low.tar.bz2' `
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-low.tar.bz2' `
        'sherpa_fr_vits.zip'
}

if ($PackDeVoice) {
    Pack-SherpaVoiceZip `
        'vits-piper-de_DE-thorsten-low.tar.bz2' `
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-thorsten-low.tar.bz2' `
        'sherpa_de_vits.zip'
}

if ($PackEsVoice) {
    Pack-SherpaVoiceZip `
        'vits-piper-es_ES-carlfm-x_low.tar.bz2' `
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-carlfm-x_low.tar.bz2' `
        'sherpa_es_vits.zip'
}

if ($PackRuVoice) {
    Pack-SherpaVoiceZip `
        'vits-piper-ru_RU-ruslan-medium.tar.bz2' `
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-ruslan-medium.tar.bz2' `
        'sherpa_ru_vits.zip'
}

$flagPath = Join-Path $SherpaDir 'native_sherpa_enabled.flag'
Set-Content -Path $flagPath -Value "enabled $(Get-Date -Format o)" -Encoding ascii
Write-Host ""
Write-Host "Next: DevEco -> Build -> Clean Project -> Rebuild -> Run on device."
Write-Host "HiLog should show: Silero TTS linked=true build=...Sherpa-ONNX [sherpa-v5]"
Write-Host "Then install all voice packs in app (sherpa_*_vits.zip if bundled)."
