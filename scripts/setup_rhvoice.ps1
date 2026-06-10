# Clone or update RHVoice under third_party/rhvoice
# Usage: .\scripts\setup_rhvoice.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Dest = Join-Path $Root 'third_party\rhvoice'
$Url = 'https://github.com/RHVoice/RHVoice.git'

if (Test-Path (Join-Path $Dest '.git')) {
    Write-Host "[skip] RHVoice already at $Dest"
    exit 0
}

New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
Write-Host "[clone] $Url -> $Dest"
cmd /c "git clone --depth 1 `"$Url`" `"$Dest`""
if ($LASTEXITCODE -ne 0) { throw "git clone RHVoice failed" }
Write-Host "[ok] RHVoice ready"
