# 将 third_party/ohos/piper_voices/<iso>/ 打包为 resfile/piper_<iso>_voice.zip
# zip 内路径: piper/<iso>/*.onnx + *.onnx.json（与 SileroModelPaths 一致）
# 用法:
#   .\scripts\pack_piper_voices.ps1           # 打包全部已下载语种
#   .\scripts\pack_piper_voices.ps1 -Iso de   # 仅德语

param(
    [string]$Iso = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SrcRoot = Join-Path $Root 'third_party\ohos\piper_voices'
$ResDir = Join-Path $Root 'entry\src\main\resources\resfile'
$ManifestPath = Join-Path $Root 'scripts\piper_voices_manifest.json'

if (-not (Test-Path $SrcRoot)) {
    throw "Run scripts\setup_piper_voices.ps1 first — missing $SrcRoot"
}
$all = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$wanted = @()
if ($Iso.Trim().Length -gt 0) {
    $wanted = $Iso.Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_.Length -gt 0 }
}
$entries = @($all)
if ($wanted.Count -gt 0) {
    $entries = @($all | Where-Object { $wanted -contains $_.iso })
}

New-Item -ItemType Directory -Force -Path $ResDir | Out-Null
$packed = 0
foreach ($e in $entries) {
    $langSrc = Join-Path $SrcRoot $e.iso
    $onnx = Join-Path $langSrc "$($e.voiceKey).onnx"
    $cfg = Join-Path $langSrc "$($e.voiceKey).onnx.json"
    if (-not (Test-Path $onnx)) {
        Write-Host "[skip] $($e.iso) — missing $onnx (run setup_piper_voices.ps1)" -ForegroundColor Yellow
        continue
    }
    if (-not (Test-Path $cfg)) {
        Write-Host "[skip] $($e.iso) — missing config" -ForegroundColor Yellow
        continue
    }
    $zipOut = Join-Path $ResDir "piper_$($e.iso)_voice.zip"
    if (Test-Path $zipOut) { Remove-Item -Force $zipOut }
    python -c @"
import json, zipfile, os
lang_src = r'$langSrc'
iso = r'$($e.iso)'
zip_path = r'$zipOut'
arc_prefix = os.path.join('piper', iso)
for name in os.listdir(lang_src):
    if name.endswith('.onnx.json'):
        cfg_path = os.path.join(lang_src, name)
        with open(cfg_path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
        if not cfg.get('phoneme_type') and isinstance(cfg.get('espeak'), dict) and cfg['espeak'].get('voice'):
            cfg['phoneme_type'] = 'espeak'
            with open(cfg_path, 'w', encoding='utf-8') as f:
                json.dump(cfg, f, ensure_ascii=False)
            print('patched phoneme_type=espeak', cfg_path)
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for name in os.listdir(lang_src):
        full = os.path.join(lang_src, name)
        if os.path.isfile(full):
            zf.write(full, os.path.join(arc_prefix, name))
print('packed', zip_path, os.path.getsize(zip_path))
"@
    if ($LASTEXITCODE -ne 0) { throw "zip failed for $($e.iso)" }
    $packed++
}
Write-Host "Packed $packed Piper voice zip(s) -> $ResDir" -ForegroundColor Green
Write-Host "DevEco Clean + Rebuild, reinstall app, then install voice in 朗读语言"
