# 配置 Silero TTS 所需的 PyTorch Mobile（libpytorch_jni_lite）与头文件
# 用法：.\scripts\setup_pytorch_mobile.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PtDir = Join-Path $Root 'third_party\ohos\pytorch_android'
$Aar = Join-Path $PtDir 'pytorch_android_lite-2.1.0.aar'
$AarUrl = 'https://repo1.maven.org/maven2/org/pytorch/pytorch_android_lite/2.1.0/pytorch_android_lite-2.1.0.aar'

if (-not (Test-Path $PtDir)) { New-Item -ItemType Directory -Path $PtDir -Force | Out-Null }
if (-not ((Test-Path $Aar) -and (Get-Item $Aar).Length -gt 1000000)) {
    Write-Host "[download] PyTorch Android Lite AAR..."
    Invoke-WebRequest -Uri $AarUrl -OutFile $Aar -UseBasicParsing
}

$Zip = Join-Path $PtDir 'pytorch.zip'
Copy-Item $Aar $Zip -Force
$Extracted = Join-Path $PtDir 'extracted'
if (-not (Test-Path (Join-Path $Extracted 'jni\arm64-v8a\libpytorch_jni_lite.so'))) {
    if (Test-Path $Extracted) { Remove-Item $Extracted -Recurse -Force }
    Expand-Archive -Path $Zip -DestinationPath $Extracted -Force
}

$IncSrc = 'D:\Python\Python314\Lib\site-packages\torch\include'
if (-not (Test-Path $IncSrc)) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py) {
        $IncSrc = & python -c "import torch, os; print(os.path.join(os.path.dirname(torch.__file__), 'include'))"
    }
}
$LibTorchRoot = Join-Path $Root 'third_party\ohos\libtorch'
$IncDst = Join-Path $LibTorchRoot 'include'
$HeadersStamp = Join-Path $LibTorchRoot 'pytorch_headers_ready.stamp'
if (Test-Path $IncSrc) {
    if (Test-Path $IncDst) { cmd /c "rmdir `"$IncDst`"" 2>$null }
    cmd /c "mklink /J `"$IncDst`" `"$IncSrc`"" 2>$null
    if (-not (Test-Path $IncDst)) { Copy-Item -Recurse $IncSrc $IncDst -Force }
    if (-not (Test-Path (Join-Path $IncDst 'torch\csrc\jit\mobile\module.h'))) {
        throw "torch mobile headers missing under $IncDst"
    }
    Set-Content -Path $HeadersStamp -Value "ok $(Get-Date -Format o)" -Encoding ascii
    Write-Host "[ok] headers -> $IncDst"
} else {
    Write-Warning "torch include not found; install PyTorch: pip install torch"
}

Write-Host "[info] Android jni libs kept under third_party\ohos\pytorch_android\extracted\jni"
Write-Host "       OHOS 需自行交叉编译 libpytorch_ohos.so 并放入 entry\src\main\libs\<abi>\"
Write-Host "       或先运行: .\scripts\setup_onnxruntime_ohos.ps1（ONNX 路线，见 build_silero_tts_ohos.md）"

Write-Host ""
Write-Host "Done. Rebuild HAP in DevEco (Release/Debug arm64)."
