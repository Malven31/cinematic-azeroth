# Gallery

Screenshots for the CurseForge gallery, and the animation for the description, go in this folder.

`private/` is ignored by git. It keeps the originals that don't belong in the repository: captures too large to commit, and screenshots showing a character name. CurseForge shows each image with a title and a description, so each shot below has both ready to paste.

## The animation

`cinematic_azeroth.gif`: a few seconds of pressing the key in a pretty spot. The interface disappears, the bars slide in, the camera turns a little, then the key again and everything comes back. The description and the README load it from `https://raw.githubusercontent.com/Malven31/cinematic-azeroth/main/curseforge/gallery/cinematic_azeroth.gif`, so keep that name and keep the repository public. Their lines for it are commented out until the file exists.

Keep it under about 10 MB: an `ffmpeg` palette pass (`palettegen=stats_mode=diff`, `paletteuse=diff_mode=rectangle`), then `magick in.gif -fuzz 4% -layers Optimize out.gif`. That took Kong UI Hider's GIF from 60 MB to 9.6 MB at the same size and frame rate.

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
