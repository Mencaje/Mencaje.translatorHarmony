# Batch-commit and push large binary assets to Gitee (SSH). ~100MB per push.
param(
    [int]$MaxBatchMB = 100,
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

$env:GIT_AUTHOR_NAME = 'mencaje'
$env:GIT_AUTHOR_EMAIL = 'mencaje@gitee.com'
$env:GIT_COMMITTER_NAME = 'mencaje'
$env:GIT_COMMITTER_EMAIL = 'mencaje@gitee.com'

$roots = @(
    'entry/src/main/resources/resfile',
    'entry/src/main/resources/rawfile',
    'entry/libs',
    'third_party/silero_lj_16000.jit',
    'third_party/tts/SummerTTS/models',
    'third_party/ohos/piperplus_pack_work',
    'third_party/ohos/onnxruntime/prebuilt',
    'third_party/ohos/piper_voices',
    'third_party/models'
)

$allFiles = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    if ((Get-Item $root) -is [System.IO.FileInfo]) {
        $allFiles.Add([PSCustomObject]@{ Path = $root; Size = (Get-Item $root).Length })
        continue
    }
    Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        $tracked = git ls-files --error-unmatch $rel 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        $allFiles.Add([PSCustomObject]@{ Path = $rel; Size = $_.Length })
    }
}

$sorted = $allFiles | Sort-Object Size -Descending
Write-Host "Pending untracked asset files: $($sorted.Count), total $([math]::Round(($sorted | Measure-Object Size -Sum).Sum/1MB,1)) MB"

$batches = New-Object System.Collections.Generic.List[object]
$current = New-Object System.Collections.Generic.List[string]
$currentSize = 0L
$maxBytes = [int64]$MaxBatchMB * 1MB

foreach ($f in $sorted) {
    if ($f.Size -gt $maxBytes -and $current.Count -eq 0) {
        $batches.Add([PSCustomObject]@{ Files = @($f.Path); Size = $f.Size; Index = $batches.Count + 1 })
        continue
    }
    if ($currentSize + $f.Size -gt $maxBytes -and $current.Count -gt 0) {
        $batches.Add([PSCustomObject]@{ Files = $current.ToArray(); Size = $currentSize; Index = $batches.Count + 1 })
        $current = New-Object System.Collections.Generic.List[string]
        $currentSize = 0L
    }
    $current.Add($f.Path)
    $currentSize += $f.Size
}
if ($current.Count -gt 0) {
    $batches.Add([PSCustomObject]@{ Files = $current.ToArray(); Size = $currentSize; Index = $batches.Count + 1 })
}

Write-Host "Planned batches: $($batches.Count)"
$ok = 0
$fail = 0
foreach ($b in $batches) {
    $idx = $b.Index
    $mb = [math]::Round($b.Size / 1MB, 1)
    Write-Host "`n=== Batch $idx / $($batches.Count) ($mb MB, $($b.Files.Count) files) ==="
    foreach ($p in $b.Files) {
        git add -f -- $p
        if ($LASTEXITCODE -ne 0) { throw "git add failed: $p" }
    }
    git add -f .gitignore 2>$null
    $msg = "assets batch $idx/$($batches.Count): add binary resources (${mb}MB)"
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Nothing to commit in batch $idx, skip."
        continue
    }
    $pushed = $false
    for ($try = 1; $try -le 3; $try++) {
        Write-Host "Push attempt $try ..."
        git push origin main 2>&1
        if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
        Start-Sleep -Seconds 10
    }
    if ($pushed) {
        $ok++
        Write-Host "Batch $idx OK"
    } else {
        $fail++
        Write-Host "Batch $idx FAILED - stop. Re-run script to continue."
        exit 1
    }
}
Write-Host "`nDone. Success: $ok, Failed: $fail"
