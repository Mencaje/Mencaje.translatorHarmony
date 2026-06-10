# 与 entry/src/main/ets/constants/SplashColdStartSpec.ets 保持相同数值
$screenW = 1080
$screenH = 2400
$logoWidthRatio = 168.0 / 360.0
$brandWidthRatio = 0.78
$brandMaxW = 1080
$bottomMargin = 40

$root = Split-Path $PSScriptRoot -Parent
$media = Join-Path $root "entry\src\main\resources\base\media"
$logoPath = Join-Path $media "splash_logo.png"
$brandPath = Join-Path $media "splash_brand_bottom.png"
$outPath = Join-Path $media "splash_start_composite.png"

Add-Type -AssemblyName System.Drawing
$logoW = [int]($logoWidthRatio * $screenW)
$brandW = [int]([Math]::Min($screenW * $brandWidthRatio, $brandMaxW))
$canvas = New-Object System.Drawing.Bitmap $screenW, $screenH
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(255, 0, 0, 0))
$logo = [System.Drawing.Image]::FromFile($logoPath)
$logoX = [int](($screenW - $logoW) / 2)
$logoY = [int](($screenH - $logoW) / 2)
$g.DrawImage($logo, $logoX, $logoY, $logoW, $logoW)
$brand = [System.Drawing.Image]::FromFile($brandPath)
$brandH = [int]($brand.Height * ($brandW / [double]$brand.Width))
$brandX = [int](($screenW - $brandW) / 2)
$brandY = $screenH - $bottomMargin - $brandH
$g.DrawImage($brand, $brandX, $brandY, $brandW, $brandH)
$g.Dispose(); $logo.Dispose(); $brand.Dispose()
$canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
Write-Host "OK: $outPath brandY=$brandY margin=$bottomMargin"
