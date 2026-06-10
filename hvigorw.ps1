# 在本机命令行 / 外部终端打包 HAP 时使用（DevEco 自带 jbr）
$ErrorActionPreference = 'Stop'

$DevEcoRoot = 'D:\deveco studio'
$env:JAVA_HOME = Join-Path $DevEcoRoot 'jbr'
$env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH

$Node = Join-Path $DevEcoRoot 'tools\node\node.exe'
$Hvigorw = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.js'

if (-not (Test-Path $Node)) { throw "找不到 Node: $Node" }
if (-not (Test-Path $Hvigorw)) { throw "找不到 hvigorw: $Hvigorw" }
if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
  throw "找不到 Java，请确认 DevEco 安装在 $DevEcoRoot"
}

Set-Location $PSScriptRoot

# Sherpa .so 不在 git 里；清 IDE 缓存后 entry/libs 可能为空，会导致 stub 包
$SherpaApi = Join-Path $PSScriptRoot 'entry\libs\arm64-v8a\libsherpa-onnx-c-api.so'
if (-not (Test-Path $SherpaApi)) {
    Write-Host '[hvigorw] Sherpa libs missing — running setup_sherpa_ohos.ps1 ...' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'scripts\setup_sherpa_ohos.ps1')
}

# 先停掉旧 daemon（否则仍可能用「没有 java」时的环境）
& $Node $Hvigorw --stop-daemon 2>$null

$hvigorArgs = @(
  '--mode', 'module',
  '-p', 'module=entry@default',
  '-p', 'product=default',
  '-p', 'requiredDeviceType=phone',
  'assembleHap',
  '--no-daemon'
)
if ($args.Count -gt 0) {
  $hvigorArgs = $args
}

& $Node $Hvigorw @hvigorArgs
exit $LASTEXITCODE
