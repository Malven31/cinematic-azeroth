# Rebuilds curseforge/gallery/cinematic_azeroth.gif from the original capture, which git ignores:
# curseforge/gallery/private/cinematic_azeroth-original.gif (1902x970, 118 frames, 8.15 s).
#
#   powershell -File scripts/make-gif.ps1
#
# 1. Other players' names that can be read are blurred one by one, in the frames where the interface shows:
#    frames 0 to 10, before cinematic mode starts, and frames 107 to 117, after it ends. Each name (or group
#    of names close together) gets a small box that follows it. The far crowd's tiny names are left.
# 2. 10 fps, 720 px wide.
# 3. A palette pass (ffmpeg), then ImageMagick drops what doesn't change between frames (fuzz 4%).
# Needs ffmpeg and ImageMagick (magick) on the PATH.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$original = Join-Path $root 'curseforge\gallery\private\cinematic_azeroth-original.gif'
$output = Join-Path $root 'curseforge\gallery\cinematic_azeroth.gif'
$palette = Join-Path ([System.IO.Path]::GetTempPath()) 'cinematic_azeroth-palette.gif'
if (-not (Test-Path -LiteralPath $original)) { throw "The original capture is missing: $original" }

# Each box: its size, and its top-left corner (pixels of the original) at key frames measured on the
# capture, as @(frame, x, y). Between two key frames the box moves in a straight line. A box is shown
# from its first key frame to its last. Where the camera speeds up or turns, key frames are closer.
# blur: the Gaussian blur's sigma, 4 unless given. The names at the end are bigger (the camera is
# closer), and sigma 4 left them readable there, so those boxes blur more.
$boxes = @(
    # Frames 0-10, before cinematic mode starts.
    @{ name = 'Holyfeet Goon, and the guild under it'; w = 114; h = 42; keys = @(@(0,657,447), @(1,647,448), @(2,642,448), @(3,623,442), @(4,618,439), @(5,615,434), @(10,581,434)) },
    @{ name = 'Ragnor Dracinis, Stephanie Turner, Emma Lockhaert'; w = 164; h = 44; keys = @(@(0,853,391), @(1,845,391), @(2,842,390), @(3,827,385), @(4,822,382), @(5,820,376), @(10,795,375)) },
    @{ name = 'Doi Gg'; w = 46; h = 26; keys = @(@(0,729,425), @(1,721,425), @(2,717,424), @(3,701,418), @(4,696,416), @(5,692,411), @(10,663,411)) },
    @{ name = 'Renato Gallina'; w = 76; h = 26; keys = @(@(0,507,346), @(1,497,345), @(2,493,345), @(3,472,338), @(4,465,335), @(5,459,328), @(10,418,325)) },
    # Frames 107-117, after cinematic mode ends: the camera is closer, so more names can be read.
    @{ name = 'Renato Gallina (end)'; w = 92; h = 24; blur = 7; keys = @(@(107,260,254), @(112,150,247), @(117,133,259)) },
    @{ name = 'Arethil Stormborn'; w = 86; h = 22; blur = 7; keys = @(@(107,465,396), @(112,390,406), @(117,400,429)) },
    # One key frame: the comma keeps PowerShell from flattening @(@(...)) into a single array.
    @{ name = 'Sergette Heinikus (frame 109 only)'; w = 90; h = 24; blur = 7; keys = @(, @(109,470,408)) },
    @{ name = 'Holyfeet Goon, and the guild under it (end)'; w = 160; h = 50; blur = 9; keys = @(@(107,420,445), @(112,323,457), @(117,275,476)) },
    @{ name = 'Jackson Lamar'; w = 90; h = 26; blur = 7; keys = @(@(107,759,410), @(112,626,416), @(117,512,413)) },
    @{ name = 'Linhai Xian, Blackwidow Scarlet, Doi Gg'; w = 110; h = 58; blur = 7; keys = @(@(107,723,410), @(112,662,423), @(117,675,444)) },
    @{ name = 'Glisnea Wardene, Anubisa Thegreat and her guild'; w = 190; h = 42; blur = 7; keys = @(@(107,874,419), @(112,819,431), @(117,835,455)) },
    @{ name = 'Ragnor Dracinis, Emma Lockhaert (end)'; w = 148; h = 58; blur = 8; keys = @(@(107,994,368), @(112,947,379), @(117,965,396)) },
    @{ name = 'Stephanie Turner (end)'; w = 94; h = 24; blur = 7; keys = @(@(107,1148,384), @(112,1103,396), @(117,1129,416)) },
    @{ name = 'Henny Zippa'; w = 66; h = 22; blur = 7; keys = @(@(107,1086,446), @(110,1046,454), @(112,1035,460), @(117,1056,484)) },
    @{ name = 'Dullahanz Plantmedic'; w = 94; h = 22; blur = 7; keys = @(@(108,1125,426), @(110,1101,432), @(112,1091,437), @(117,1115,460)) },
    @{ name = 'Celdra Dawnstar, and her guild'; w = 78; h = 30; blur = 7; keys = @(@(108,1244,439), @(110,1220,445), @(112,1211,450), @(117,1240,474)) }
)

# An ffmpeg expression for one coordinate (index 1: x, 2: y) of a box, frame by frame. $frame is the
# frame number as the filter sees it: crop counts frames from 0 (n), but overlay's x and y count them
# from 1, so it gets (n-1). (Its enable option counts from 0.) Checked on this capture on 2026-11-16.
function Get-Path($keys, [int]$index, [string]$frame) {
    if ($keys.Count -eq 1) { return "$($keys[0][$index])" }
    $first, $last = $keys[0][0], $keys[-1][0]
    $f = "clip($frame,$first,$last)"
    $segment = { param($a, $b) "$($a[$index])+($($b[$index])-$($a[$index]))*($f-$($a[0]))/$($b[0]-$a[0])" }
    $expr = & $segment $keys[-2] $keys[-1]
    for ($i = $keys.Count - 3; $i -ge 0; $i--) {
        $expr = "if(lt($f,$($keys[$i + 1][0])),$(& $segment $keys[$i] $keys[$i + 1]),$expr)"
    }
    return $expr
}

# gbrp first: blurring the GIF's own pixel format left bright green dashes in the small boxes.
$graph = "[0:v]format=gbrp,split=$($boxes.Count + 1)[base]" + ((1..$boxes.Count | ForEach-Object { "[s$_]" }) -join '') + ';'
$previous = 'base'
for ($i = 1; $i -le $boxes.Count; $i++) {
    $box = $boxes[$i - 1]
    $first, $last = $box.keys[0][0], $box.keys[-1][0]
    $sigma = if ($box.blur) { $box.blur } else { 4 }
    $graph += "[s$i]crop=w=$($box.w):h=$($box.h):x='$(Get-Path $box.keys 1 'n')':y='$(Get-Path $box.keys 2 'n')',gblur=sigma=$sigma[b$i];"
    $graph += "[$previous][b$i]overlay=x='$(Get-Path $box.keys 1 '(n-1)')':y='$(Get-Path $box.keys 2 '(n-1)')':enable='between(n,$first,$last)'[o$i];"
    $previous = "o$i"
}
if ($args -contains '-GraphOnly') { return "$graph|$previous" }
$graph += "[$previous]fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=diff_mode=rectangle"

& ffmpeg -v error -y -i $original -filter_complex $graph $palette
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit code $LASTEXITCODE)" }
& magick $palette -fuzz 4% -layers Optimize $output
if ($LASTEXITCODE -ne 0) { throw "magick failed (exit code $LASTEXITCODE)" }
Remove-Item -LiteralPath $palette
Write-Output "$output ($([math]::Round((Get-Item -LiteralPath $output).Length / 1MB, 1)) MB)"
