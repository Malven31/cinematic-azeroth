# Gallery

Screenshots for the CurseForge gallery, and the animation for the description, go in this folder.

`private/` is ignored by git. It keeps the originals that don't belong in the repository: captures too large to commit, and screenshots showing a character name. CurseForge shows each image with a title and a description, so each shot below has both ready to paste.

## The animation

`cinematic_azeroth.gif` shows cinematic mode turning on while the character runs through a city. The interface and the names disappear, and the letterbox bars slide in. The description and the README show it under the introduction; the description loads it from `https://raw.githubusercontent.com/Malven31/cinematic-azeroth/main/curseforge/gallery/cinematic_azeroth.gif`, so keep that name and keep the repository public.

How it was made (2026-11-16), from the capture kept in `private/cinematic_azeroth-original.gif` (1902×970, 118 frames, 8.15 s, 112.9 MB):

1. **Other players' names blurred.** In the first 11 frames, before cinematic mode hides them, players' names and guild tags show in the street. A 860×170 box at (250, 330) is blurred in those frames only. The minimap and the NPC names still visibly disappear.
2. **10 fps, 720 px wide** (720×367): 82 frames, still 8.2 s, looping forever.
3. The same two passes as Kong UI Hider's GIF: an `ffmpeg` palette pass (`palettegen=stats_mode=diff`, `paletteuse=diff_mode=rectangle`), then `magick in.gif -fuzz 4% -layers Optimize out.gif`. Result: **11.5 MB**.

The command, from the repository root:

```powershell
ffmpeg -i curseforge/gallery/private/cinematic_azeroth-original.gif -filter_complex "[0:v]split[base][tmp];[tmp]crop=860:170:250:330,boxblur=14:2[bl];[base][bl]overlay=250:330:enable='lte(n\,10)',fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=diff_mode=rectangle" palette.gif
magick palette.gif -fuzz 4% -layers Optimize curseforge/gallery/cinematic_azeroth.gif
```

The size had to shrink, unlike Kong's. The camera moves in every frame, so almost every pixel changes, and the fuzz pass has little to drop: at full size the two passes only went from 112.9 MB to 97.4 MB. Other sizes measured, all without the blur:

| Width | Frame rate | Size |
|---|---|---|
| 960 px | about 14.5 fps | 27 MB |
| 960 px | 10 fps | 19.9 MB |
| 800 px | about 14.5 fps | 19.1 MB |
| 800 px | 10 fps | 14.1 MB |
| 720 px | 10 fps | 11.4 MB |

## Screenshots

Tips:

- Take them with the in-game screenshot key (Print Screen). They are saved in `_forever_\Screenshots`.
- Hide the names of other players and your own character, and keep the chat free of private messages.
- The same spot and camera angle for "before" and "after" makes the difference obvious.

| File | What to show | Title | Description |
|---|---|---|---|
| `01-before.jpg` | A beautiful spot with your usual interface | Before | Your interface, as usual. |
| `02-cinematic.jpg` | The same spot in cinematic mode | Cinematic mode | One key: the interface and the nameplates are gone, and the letterbox bars are in. |
| `03-vendor.jpg` | A vendor's window and the bags open in cinematic mode | Interaction windows | The windows an NPC opens, and your bags, appear alone over the scene. |
| `04-quest-marks.jpg` | Quest givers with their ! and ?, nothing else on screen | Quest marks | Keep the marks over quest givers, with no nameplates or names. |
| `05-flight.jpg` | A flight master's flight in cinematic mode | Flights | Take a flight and cinematic mode turns on by itself, then off on landing. |
| `06-talk.jpg` | The chat typing bar with a line being typed, a speech bubble over your character | Talk in cinematic mode | Keep the speech bubbles, and the typing bar shows while you type. |
| `07-options.jpg` | The options page (`/cinema`) | Options | Choose your key, what goes, what stays, and the shape of the bars. |
| `08-formats.jpg` | The same view with the 2.39:1 and 1.85:1 buttons | Film formats | Bars for the 2.39:1, 2.00:1 or 1.85:1 film formats, on any screen. |

Rename or drop shots freely.
