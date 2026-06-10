# 下载 rhasspy/piper-voices (v1.0.0) 到本地 third_party/ohos/piper_voices/
# 用法:
#   .\scripts\setup_piper_voices.ps1              # 全部 29 种 Piper 新语种
#   .\scripts\setup_piper_voices.ps1 -Iso de      # 仅德语
#   .\scripts\setup_piper_voices.ps1 -Iso de,fr,ar

param(
    [string]$Iso = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ManifestPath = Join-Path $Root 'scripts\piper_voices_manifest.json'
$OutRoot = Join-Path $Root 'third_party\ohos\piper_voices'
$HfBase = 'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0'

function Invoke-Download([string]$Url, [string]$OutFile, [int]$MinBytes = 8000) {
    if (Test-Path $OutFile) {
        if ((Get-Item $OutFile).Length -ge $MinBytes) { return }
    }
    $candidates = @($Url)
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

if (-not (Test-Path $ManifestPath)) { throw "Missing $ManifestPath" }
$all = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$wanted = @()
if ($Iso.Trim().Length -gt 0) {
    $wanted = $Iso.Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_.Length -gt 0 }
}
$entries = @($all)
if ($wanted.Count -gt 0) {
    $entries = @($all | Where-Object { $wanted -contains $_.iso })
    if ($entries.Count -eq 0) { throw "No manifest entries for: $Iso" }
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$ok = 0
foreach ($e in $entries) {
    $langDir = Join-Path $OutRoot $e.iso
    New-Item -ItemType Directory -Force -Path $langDir | Out-Null
    $onnx = Join-Path $langDir "$($e.voiceKey).onnx"
    $cfg = Join-Path $langDir "$($e.voiceKey).onnx.json"
    $onnxUrl = "$HfBase/$($e.hfPath)/$($e.voiceKey).onnx?download=true"
    $cfgUrl = "$HfBase/$($e.hfPath)/$($e.voiceKey).onnx.json?download=true"
    Write-Host "`n=== $($e.iso) $($e.voiceKey) ===" -ForegroundColor Cyan
    Invoke-Download $onnxUrl $onnx -MinBytes 50000000
    Invoke-Download $cfgUrl $cfg -MinBytes 256
    $ok++
}
Write-Host "`nDone: $ok voice(s) under $OutRoot" -ForegroundColor Green
Write-Host "Next: .\scripts\pack_piper_voices.ps1 [-Iso de] then DevEco Clean+Rebuild"
