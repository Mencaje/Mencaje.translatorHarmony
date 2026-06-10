# 拉取中/日/韩离线 TTS 源码到 third_party/tts（仅下载，不接进 HAP）
# 用法：
#   .\scripts\setup_tts_zh_ja_ko.ps1
#   .\scripts\setup_tts_zh_ja_ko.ps1 -KoreanRepoUrl "https://github.com/你的账号/KoreanTTS-cpp.git"

param(
    [string]$KoreanRepoUrl = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TtsDir = Join-Path $Root 'third_party\tts'

function Clone-Repo([string]$Name, [string]$Url, [string]$Branch = '') {
    $dest = Join-Path $TtsDir $Name
    if (Test-Path (Join-Path $dest '.git')) {
        Write-Host "[skip] $Name already cloned -> $dest"
        return
    }
    if (Test-Path $dest) {
        Remove-Item -Recurse -Force $dest
    }
    New-Item -ItemType Directory -Path $TtsDir -Force | Out-Null
    $urls = @($Url)
    if ($Url -match '^https://github\.com/') {
        $urls += "https://ghproxy.net/$Url"
        $urls += "https://mirror.ghproxy.com/$Url"
    }
    $ok = $false
    foreach ($u in $urls) {
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Write-Host "[clone] git clone --depth 1 $u"
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        cmd /c "git clone --depth 1 `"$u`" `"$dest`" 2>&1"
        $ErrorActionPreference = $prevEap
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $dest '.git'))) {
            $ok = $true
            break
        }
    }
    if (-not $ok) {
        Write-Host "[fail] git clone failed: $Name (retry later or clone manually)" -ForegroundColor Red
        return
    }
    Write-Host "[ok] $Name -> $dest"
}

Clone-Repo 'SummerTTS' 'https://github.com/huakunyang/SummerTTS.git'
Clone-Repo 'piper-plus' 'https://github.com/ayutaz/piper-plus.git'

$koDest = Join-Path $TtsDir 'KoreanTTS-cpp'
if ($KoreanRepoUrl.Length -gt 0) {
    Clone-Repo 'KoreanTTS-cpp' $KoreanRepoUrl
} elseif (-not (Test-Path (Join-Path $koDest '.git'))) {
    New-Item -ItemType Directory -Path $koDest -Force | Out-Null
    $readme = Join-Path $koDest 'README.md'
    Set-Content -Path $readme -Encoding utf8 -Value @(
        '# KoreanTTS-cpp',
        '',
        'Clone your Korean C++ TTS repo here, e.g.:',
        '  git clone --depth 1 <repo-url> .',
        '',
        'Or: .\scripts\setup_tts_zh_ja_ko.ps1 -KoreanRepoUrl "https://github.com/xxx/KoreanTTS-cpp.git"',
        '',
        'Update OpenSourceLicenseData.ets licenseUrl/repoUrl after you know the repo.'
    )
    Write-Host "[warn] KoreanTTS-cpp: no repo URL; placeholder at $koDest" -ForegroundColor Yellow
}

$packZh = Join-Path $Root 'scripts\pack_summertts_zh_rawfile.ps1'
if ((Test-Path $packZh) -and (Test-Path (Join-Path $TtsDir 'SummerTTS\models\single_speaker_fast.bin'))) {
    & $packZh
}

Write-Host ""
Write-Host "Done. Sources under: $TtsDir"
Write-Host "Chinese: SummerTTS wired in NAPI; run pack_summertts_zh_rawfile.ps1 if rawfile missing."
Write-Host "Next: piper-plus (ja), then KoreanTTS-cpp (ko)."
