# Rebuilds curseforge/gallery/cinematic_azeroth.gif from the original capture, which git ignores:
# curseforge/gallery/private/cinematic_azeroth-original.gif (1902x970, 118 frames, 8.15 s).
#
#   powershell -File scripts/make-gif.ps1
#
# 1. The other players' names readable in the first 11 frames, before cinematic mode hides them, are blurred
#    one by one: each group of names gets a small box that follows it. The far crowd's tiny names are left.
# 2. 10 fps, 720 px wide.
# 3. A palette pass (ffmpeg), then ImageMagick drops what doesn't change between frames (fuzz 4%).
# Needs ffmpeg and ImageMagick (magick) on the PATH.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$original = Join-Path $root 'curseforge\gallery\private\cinematic_azeroth-original.gif'
$output = Join-Path $root 'curseforge\gallery\cinematic_azeroth.gif'
$palette = Join-Path ([System.IO.Path]::GetTempPath()) 'cinematic_azeroth-palette.gif'
if (-not (Test-Path -LiteralPath $original)) { throw "The original capture is missing: $original" }

# Each box: its size, and its top-left corner in frames 0 to 5 and in frame 10 (pixels of the original),
# measured on the capture. The camera speeds up over the first frames, so frames 0 to 5 are measured
# one by one; frames 6 to 9 are interpolated between 5 and 10.
$boxes = @(
    @{ name = 'Holyfeet Goon, and the guild under it'; w = 114; h = 42; at = @(@(657,447), @(647,448), @(642,448), @(623,442), @(618,439), @(615,434), @(581,434)) },
    @{ name = 'Ragnor Dracinis, Stephanie Turner, Emma Lockhaert'; w = 164; h = 44; at = @(@(853,391), @(845,391), @(842,390), @(827,385), @(822,382), @(820,376), @(795,375)) },
    @{ name = 'Doi Gg'; w = 46; h = 26; at = @(@(729,425), @(721,425), @(717,424), @(701,418), @(696,416), @(692,411), @(663,411)) },
    @{ name = 'Renato Gallina'; w = 76; h = 26; at = @(@(507,346), @(497,345), @(493,345), @(472,338), @(465,335), @(459,328), @(418,325)) }
)
$lastBlurredFrame = 10

# An ffmpeg expression for one coordinate, frame by frame. $frame is the frame number as the filter
# sees it: crop counts frames from 0 (n), but overlay's x and y count them from 1, so it gets (n-1).
# (Its enable option counts from 0.) Checked on this capture on 2026-11-16.
function Get-Path([int[]]$values, [string]$frame) {
    $expr = "$($values[5])+($($values[6])-$($values[5]))*(min($frame,10)-5)/5"
    for ($i = 4; $i -ge 0; $i--) { $expr = "if(eq($frame,$i),$($values[$i]),$expr)" }
    return $expr
}

# gbrp first: blurring the GIF's own pixel format left bright green dashes in the small boxes.
$graph = "[0:v]format=gbrp,split=$($boxes.Count + 1)[base]" + ((1..$boxes.Count | ForEach-Object { "[s$_]" }) -join '') + ';'
$previous = 'base'
for ($i = 1; $i -le $boxes.Count; $i++) {
    $box = $boxes[$i - 1]
    $xs = [int[]]($box.at | ForEach-Object { $_[0] })
    $ys = [int[]]($box.at | ForEach-Object { $_[1] })
    $graph += "[s$i]crop=w=$($box.w):h=$($box.h):x='$(Get-Path $xs 'n')':y='$(Get-Path $ys 'n')',gblur=sigma=4[b$i];"
    $graph += "[$previous][b$i]overlay=x='$(Get-Path $xs '(n-1)')':y='$(Get-Path $ys '(n-1)')':enable='lte(n,$lastBlurredFrame)'[o$i];"
    $previous = "o$i"
}
$graph += "[$previous]fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=diff_mode=rectangle"

& ffmpeg -v error -y -i $original -filter_complex $graph $palette
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit code $LASTEXITCODE)" }
& magick $palette -fuzz 4% -layers Optimize $output
if ($LASTEXITCODE -ne 0) { throw "magick failed (exit code $LASTEXITCODE)" }
Remove-Item -LiteralPath $palette
Write-Output "$output ($([math]::Round((Get-Item -LiteralPath $output).Length / 1MB, 1)) MB)"
