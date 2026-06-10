# 下载 Silero TTS 模型到 entry/src/main/resources/rawfile/（编译进 HAP，设备上点「安装」即可拷贝到私有目录）
# 用法（PowerShell）：.\scripts\fetch_silero_rawfile_models.ps1
# 可选：.\scripts\fetch_silero_rawfile_models.ps1 -Only en,de

param(
    [string[]] $Only = @()
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RawDir = Join-Path $Root 'entry\src\main\resources\rawfile'
if (-not (Test-Path $RawDir)) { New-Item -ItemType Directory -Path $RawDir -Force | Out-Null }

function Export-SileroEnglishMobile {
    param([string]$PackagePt, [string]$MobileOut)
    if ((Test-Path $MobileOut) -and ((Get-Item $MobileOut).Length -gt 1000000)) {
        Write-Host "[skip] en mobile .ptl exists"
        return
    }
    Write-Host "[export] en PyTorch Mobile .ptl (requires: pip install torch)"
    $py = @"
import torch
from torch.utils.mobile_optimizer import optimize_for_mobile
imp = torch.package.PackageImporter(r'$PackagePt')
model = imp.load_pickle('tts_models', 'model')
mobile = optimize_for_mobile(model.model)
mobile._save_for_lite_interpreter(r'$MobileOut')
print('ptl bytes', __import__('os').path.getsize(r'$MobileOut'))
"@
    $tmp = Join-Path $env:TEMP "export_silero_mobile.py"
    Set-Content -Path $tmp -Value $py -Encoding UTF8
    python $tmp
}

$Models = @(
    @{ Iso = 'en'; Url = 'https://models.silero.ai/models/tts/en/v3_en.pt'; Raw = 'silero_v3_en.pt'; Dest = 'v3_en.pt' }
    @{ Iso = 'fr'; Url = 'https://models.silero.ai/models/tts/fr/v3_fr.pt'; Raw = 'silero_v3_fr.pt'; Dest = 'v3_fr.pt' }
    @{ Iso = 'de'; Url = 'https://models.silero.ai/models/tts/de/v3_de.pt'; Raw = 'silero_v3_de.pt'; Dest = 'v3_de.pt' }
    @{ Iso = 'es'; Url = 'https://models.silero.ai/models/tts/es/v3_es.pt'; Raw = 'silero_v3_es.pt'; Dest = 'v3_es.pt' }
    @{ Iso = 'ru'; Url = 'https://models.silero.ai/models/tts/ru/v5_cis_base_nostress.jit'; Raw = 'silero_v5_cis_base_nostress.jit'; Dest = 'v5_cis_base_nostress.jit' }
)

foreach ($m in $Models) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $m.Iso)) { continue }
    $out = Join-Path $RawDir $m.Raw
    if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1000000)) {
        Write-Host "[skip] $($m.Iso) already exists: $out"
        if ($m.Iso -eq 'en') {
            Export-SileroEnglishMobile $out (Join-Path $RawDir 'silero_v3_en_mobile.ptl')
        }
        continue
    }
    Write-Host "[download] $($m.Iso) -> $out"
    Invoke-WebRequest -Uri $m.Url -OutFile $out -UseBasicParsing
    $len = (Get-Item $out).Length
    if ($len -lt 1000000) {
        Remove-Item $out -Force
        throw "Download too small for $($m.Iso) ($len bytes). Check network or URL."
    }
    Write-Host "  OK $([math]::Round($len/1MB, 1)) MB"
    if ($m.Iso -eq 'en') {
        Export-SileroEnglishMobile $out (Join-Path $RawDir 'silero_v3_en_mobile.ptl')
    }
}

Write-Host ""
Write-Host "Also run: .\scripts\setup_pytorch_mobile.ps1"
Write-Host "Done. Rebuild HAP in DevEco, then install voice pack on device."
Write-Host "Raw dir: $RawDir"
