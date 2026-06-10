# Check arm64 libsilero_tts_napi.so in the last built HAP / stripped libs for [sherpa-v1].
# Usage: .\scripts\verify_hap_tts.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Test-SoMarker {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    return @{
        Path = $Path
        Sherpa = $text.Contains('[sherpa-v1]')
        Stub = $text.Contains('NO inference')
        Size = (Get-Item $Path).Length
        Time = (Get-Item $Path).LastWriteTime
    }
}

Write-Host '=== HAP / packaged TTS native check ===' -ForegroundColor Cyan

$candidates = @(
    (Join-Path $Root 'entry\build\default\intermediates\stripped_native_libs\default\arm64-v8a\libsilero_tts_napi.so'),
    (Join-Path $Root 'entry\build\default\intermediates\cmake\default\obj\arm64-v8a\libsilero_tts_napi.so'),
    (Join-Path $Root 'entry\build\default\outputs\default\entry-default-signed.hap'),
    (Join-Path $Root 'entry\build\default\outputs\default\entry-default-unsigned.hap')
)

$found = $false
foreach ($p in $candidates) {
    if ($p -like '*.hap') {
        if (-not (Test-Path $p)) { continue }
        $tmpZip = Join-Path $env:TEMP ('hap_tts_' + [guid]::NewGuid().ToString('N') + '.zip')
        $tmp = [IO.Path]::ChangeExtension($tmpZip, '')
        Copy-Item -LiteralPath $p -Destination $tmpZip -Force
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            Expand-Archive -Path $tmpZip -DestinationPath $tmp -Force
            $sos = Get-ChildItem -Path $tmp -Recurse -Filter 'libsilero_tts_napi.so' |
                Where-Object { $_.FullName -match 'arm64-v8a|x86_64' }
            foreach ($so in $sos) {
                $r = Test-SoMarker $so.FullName
                if ($null -eq $r) { continue }
                $found = $true
                $abi = if ($r.Path -match 'x86_64') { 'x86_64' } else { 'arm64-v8a' }
                Write-Host "[HAP $abi] $($r.Path)" -ForegroundColor Gray
                if ($r.Sherpa) {
                    Write-Host "  [OK] [sherpa-v1] in packaged HAP ($abi)" -ForegroundColor Green
                } else {
                    Write-Host "  [FAIL] stub in HAP ($abi)" -ForegroundColor Red
                    exit 1
                }
            }
        } finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
        }
        continue
    }
    $r = Test-SoMarker $p
    if ($null -eq $r) { continue }
    $found = $true
    Write-Host "$($r.Path)" -ForegroundColor Gray
    Write-Host "  size=$($r.Size) time=$($r.Time)" -ForegroundColor Gray
    if ($r.Sherpa) {
        Write-Host '  [OK] [sherpa-v1]' -ForegroundColor Green
    } elseif ($r.Stub) {
        Write-Host '  [FAIL] stub (NO inference)' -ForegroundColor Red
        exit 1
    } else {
        Write-Host '  [WARN] unknown build' -ForegroundColor Yellow
        exit 1
    }
}

if (-not $found) {
    Write-Host '[FAIL] No built HAP or libsilero_tts_napi.so found. Build in DevEco first.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Packaged native looks correct. Uninstall app on phone, Run again, check HiLog for linked=true [sherpa-v1].' -ForegroundColor Green
exit 0
