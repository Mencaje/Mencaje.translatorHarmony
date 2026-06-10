# Check whether debug/release .p7b includes ohos.permission.USE_FLOAT_BALL in allowed-acls.
param(
    [string]$DebugProfile = "D:/xiangmu/Mencaje.translatorHarmony/签名/调试/Mencaje.translator调试Debug.p7b",
    [string]$ReleaseProfile = "D:/xiangmu/Mencaje.translatorHarmony/签名/mencaje翻译Release.p7b"
)

$java = "D:\deveco studio\jbr\bin\java.exe"
$jar = "D:\deveco studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"
if (-not (Test-Path $java)) {
    Write-Error "DevEco JBR not found: $java"
    exit 1
}
if (-not (Test-Path $jar)) {
    Write-Error "hap-sign-tool.jar not found: $jar"
    exit 1
}

function Test-ProfileAcl([string]$label, [string]$path) {
    if (-not (Test-Path $path)) {
        Write-Host "[$label] MISSING: $path" -ForegroundColor Yellow
        return
    }
    $out = Join-Path $env:TEMP ("profile-verify-" + [guid]::NewGuid().ToString() + ".json")
    & $java -jar $jar verify-profile -inFile $path -outFile $out 2>&1 | Out-Null
    if (-not (Test-Path $out)) {
        Write-Host "[$label] verify-profile failed: $path" -ForegroundColor Red
        return
    }
    $json = Get-Content $out -Raw | ConvertFrom-Json
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    $acls = $json.content.acls.'allowed-acls'
    $bundle = $json.content.'bundle-info'.'bundle-name'
    Write-Host "[$label] bundle=$bundle path=$path"
    if ($null -eq $acls -or $acls.Count -eq 0) {
        Write-Host "  allowed-acls: (empty) -> install will fail with USE_FLOAT_BALL in module.json5" -ForegroundColor Red
    } else {
        Write-Host "  allowed-acls: $($acls -join ', ')"
        if ($acls -contains 'ohos.permission.USE_FLOAT_BALL') {
            Write-Host "  USE_FLOAT_BALL: OK" -ForegroundColor Green
        } else {
            Write-Host "  USE_FLOAT_BALL: NOT in ACL" -ForegroundColor Red
        }
    }
}

Test-ProfileAcl 'debug' $DebugProfile
Test-ProfileAcl 'release' $ReleaseProfile
