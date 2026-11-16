# Draws Cinematic Azeroth's icon: a sunset over mountains and a lake, framed by black letterbox bars.
#
#   powershell -File scripts/make-icon.ps1 -Out curseforge/logo.png -Size 512           # CurseForge avatar
#   powershell -File scripts/make-icon.ps1 -Out CinematicAzeroth/media/icon.tga -Size 64 # in-game icon
#
# The picture is drawn at four times the size and scaled down, for smooth edges. A .tga is written as
# uncompressed 32-bit BGRA with bottom-up rows, which WoW reads as an addon texture (its size must be a
# power of two). Any other extension is written as PNG.
param([Parameter(Mandatory)][string]$Out, [int]$Size = 512)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$C = [System.Drawing.Color]
$S = $Size * 4

function Hex([string]$hex, [int]$alpha = 255) {
    $v = [Convert]::ToInt32($hex.TrimStart('#'), 16)
    return $C::FromArgb($alpha, ($v -shr 16) -band 255, ($v -shr 8) -band 255, $v -band 255)
}
function Pt([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]($x * $S)), ([single]($y * $S)) }
function Rect([double]$x, [double]$y, [double]$w, [double]$h) {
    New-Object System.Drawing.RectangleF ([single]($x * $S)), ([single]($y * $S)), ([single]($w * $S)), ([single]($h * $S))
}
function Polygon([double[]]$xy) {
    $points = for ($i = 0; $i -lt $xy.Length; $i += 2) { Pt $xy[$i] $xy[$i + 1] }
    return [System.Drawing.PointF[]]$points
}
# A vertical gradient over the rectangle, through the given colours at the given positions (0 to 1).
function VerticalBrush($rect, [System.Drawing.Color[]]$colors, [single[]]$positions) {
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $colors[0], $colors[-1], 90.0
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend
    $blend.Colors = $colors
    $blend.Positions = $positions
    $brush.InterpolationColors = $blend
    return $brush
}

# The picture between the bars runs from TOP to BOTTOM; the horizon (the lake's edge) is at HORIZON.
$TOP, $BOTTOM, $HORIZON = 0.2, 0.8, 0.635

$big = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($big)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

# Sky: indigo at the top, through magenta and orange, to gold at the horizon.
$sky = Rect 0 ($TOP - 0.01) 1 ($HORIZON - $TOP + 0.02)
$g.FillRectangle((VerticalBrush $sky @((Hex '2a2d6e'), (Hex '7c3a7c'), (Hex 'd9654c'), (Hex 'ffc66e')) @(0.0, 0.45, 0.78, 1.0)), $sky)

# Sun: a soft glow, then the disc, half set behind the mountains and the lake.
$sunX, $sunY, $sunR = 0.5, 0.565, 0.115
$glowR = $sunR * 2.6
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse((Rect ($sunX - $glowR) ($sunY - $glowR) ($glowR * 2) ($glowR * 2)))
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush $glowPath
$glow.CenterColor = Hex 'ffe9b0' 150
$glow.SurroundColors = @((Hex 'ffe9b0' 0))
$g.FillPath($glow, $glowPath)
$sunRect = Rect ($sunX - $sunR) ($sunY - $sunR) ($sunR * 2) ($sunR * 2)
$g.FillEllipse((VerticalBrush $sunRect @((Hex 'fff6d8'), (Hex 'ffe08a')) @(0.0, 1.0)), $sunRect)

# Far mountains, hazy purple, opening a valley around the sun.
$far = Rect 0 0.38 1 ($HORIZON - 0.38 + 0.01)
$farBrush = VerticalBrush $far @((Hex '7a4274'), (Hex '4c2654')) @(0.0, 1.0)
$g.FillPolygon($farBrush, (Polygon @(0, $HORIZON, 0, 0.47, 0.07, 0.42, 0.13, 0.465, 0.2, 0.395, 0.27, 0.475, 0.33, 0.53, 0.4, 0.595, 0.445, $HORIZON)))
$g.FillPolygon($farBrush, (Polygon @(0.555, $HORIZON, 0.6, 0.59, 0.67, 0.515, 0.74, 0.435, 0.8, 0.485, 0.87, 0.405, 0.94, 0.465, 1, 0.445, 1, $HORIZON)))

# Near hills, almost black, with a watchtower on the right-hand ridge.
$near = Rect 0 0.42 1 ($HORIZON - 0.42 + 0.01)
$nearBrush = VerticalBrush $near @((Hex '2a1433'), (Hex '170b1f')) @(0.0, 1.0)
$g.FillPolygon($nearBrush, (Polygon @(0, $HORIZON, 0, 0.545, 0.06, 0.515, 0.12, 0.555, 0.18, 0.535, 0.26, 0.6, 0.33, $HORIZON)))
$g.FillPolygon($nearBrush, (Polygon @(0.67, $HORIZON, 0.74, 0.595, 0.8, 0.565, 0.86, 0.575, 0.92, 0.525, 1, 0.55, 1, $HORIZON)))
$g.FillRectangle($nearBrush, (Rect 0.872 0.475 0.034 0.1))
$g.FillPolygon($nearBrush, (Polygon @(0.864, 0.478, 0.889, 0.418, 0.914, 0.478)))

# Lake: the sky's colours mirrored, bright at the horizon and darker toward the viewer.
$lake = Rect 0 ($HORIZON - 0.002) 1 ($BOTTOM - $HORIZON + 0.012)
$g.FillRectangle((VerticalBrush $lake @((Hex 'e08a5a'), (Hex '9a4a6a'), (Hex '3b2257')) @(0.0, 0.35, 1.0)), $lake)

# The sun's reflection: golden streaks, narrower further down.
$streak = Hex 'ffe7a6' 210
$y = $HORIZON + 0.012
$width = 0.2
while ($y -lt $BOTTOM - 0.01) {
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $streak), (Rect ($sunX - $width / 2) $y $width 0.011))
    $y += 0.024
    $width *= 0.72
}

# The letterbox bars.
$black = New-Object System.Drawing.SolidBrush ($C::FromArgb(255, 0, 0, 0))
$g.FillRectangle($black, (Rect 0 0 1 $TOP))
$g.FillRectangle($black, (Rect 0 $BOTTOM 1 (1 - $BOTTOM)))
$g.Dispose()

# Scale down to the requested size.
$bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.DrawImage($big, (New-Object System.Drawing.Rectangle 0, 0, $Size, $Size))
$g.Dispose()
$big.Dispose()

if ($Out -match '\.tga$') {
    $lock = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $Size, $Size), [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = New-Object byte[] ($lock.Stride * $Size)
    [System.Runtime.InteropServices.Marshal]::Copy($lock.Scan0, $pixels, 0, $pixels.Length)
    $stride = $lock.Stride
    $bmp.UnlockBits($lock)
    $header = New-Object byte[] 18
    $header[2] = 2                                              # uncompressed true colour
    $header[12] = $Size -band 0xFF; $header[13] = $Size -shr 8  # width
    $header[14] = $Size -band 0xFF; $header[15] = $Size -shr 8  # height
    $header[16] = 32                                            # bits per pixel
    $header[17] = 8                                             # 8 alpha bits, bottom-left origin
    $stream = [System.IO.File]::Create($Out)
    try {
        $stream.Write($header, 0, 18)
        for ($row = $Size - 1; $row -ge 0; $row--) { $stream.Write($pixels, $row * $stride, $Size * 4) }  # BGRA, bottom row first
    } finally { $stream.Dispose() }
} else {
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
}
$bmp.Dispose()
Write-Output "$Out ($Size x $Size)"
