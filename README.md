# Cinematic Azeroth

<!-- Download badge, once the CurseForge project exists:
[![CurseForge downloads](https://img.shields.io/curseforge/dt/<projectID>?logo=curseforge&label=downloads)](https://www.curseforge.com/wow/addons/<slug>) -->

Press one key and Azeroth becomes a film: the whole interface and the nameplates disappear, and black letterbox bars slide in from the top and bottom of the screen. Press it again, or Escape, and everything comes back.

Made for **World of Warcraft: Forever**.

- [Features](FEATURES.md): every option, explained.
- [Changelog](CHANGELOG.md)

## Install

Install it from CurseForge (Forever flavor), or by hand:

1. Copy the `CinematicAzeroth` folder into `World of Warcraft\_forever_\Interface\AddOns`.
2. Restart the game.

## Quick start

1. Type `/cinema`. The options open.
2. Click the key button under **Your key**, then press the key you want (or a mouse button).
3. Press that key in the game. Press it again, or Escape, to come back.

## What it does

- **Hides everything, safely.** Your key runs Blizzard's own Toggle UI (the one on Alt+Z), so it works in combat and every window closes and reopens with Blizzard's own code.
- **Choose what else goes:** nameplates, names above heads, speech bubbles, combat numbers, and the interaction icons over NPCs and the fishing bobber. The game settings changed for this are put back exactly as they were, even after a crash.
- **Keeps what you need over the scene:** windows an NPC opens (dialog, quests, loot, vendors, flight master, trainers, bank, mail, auction house...), your bags, tooltips if you want them, and the quest marks over quest givers.
- **Talk without leaving it:** keep the speech bubbles and the chat typing bar shows while you type.
- **Combat and flights:** cinematic mode can end when a fight starts and come back after it, and turn on by itself for flight master flights.
- **Letterbox bars to taste:** height, film-format buttons (2.39:1, 2.00:1, 1.85:1), slide time, preview.

## Commands

| Command | What it does |
|---|---|
| `/cinema` | Opens the options (also in Options > AddOns > Cinematic Azeroth) |
| `/cinema test` | Shows the bars for 3 seconds |
| `/cinema debug` | Saves what is on screen into the saved variables, for a bug report |
| `/cinema watch` | Turns the diagnostics on or off (see [FEATURES.md](FEATURES.md#commands)) |
| `/cinema help` | Lists the commands |

Cinematic mode itself is only toggled by your key: only a key press can hide the interface safely.

## Good to know

- **Alt+Z** keeps hiding the interface without bars, unless you tick the option to add them there too.
- **Combat and flights:** for these, no key is pressed, so the addon shows or hides the interface itself. If errors mentioning Cinematic Azeroth appear after a fight or a flight, untick those options and use your key.
- **DynamicCam:** if its "Taxi" situation hides the interface, turn that off or untick the flights option here. With both, Escape during a flight leaves the interface invisible until you land.
- **During combat** the game doesn't let addons change the names, nameplate and interaction-icon settings. In a cinematic mode started during a fight, those go when the fight ends.

## Reporting a bug

Type `/cinema debug` while the problem shows (or `/cinema watch` for the next cinematic modes), then `/reload`. The records are in `WTF\Account\<account>\SavedVariables\CinematicAzeroth.lua`. Open an issue, or comment on the CurseForge page, with what you did, what you expected, and that file.

## Credits

By **Malven31**, made with Claude (Anthropic). The icon is the addon's own (`scripts/make-icon.ps1` draws it).

## Licence

MIT, see [LICENSE](LICENSE).

## Releasing

Releases are packaged and uploaded to CurseForge automatically when a version tag is pushed. The GitHub workflow `.github/workflows/release.yml` runs the [BigWigs packager](https://github.com/BigWigsMods/packager), following `.pkgmeta`.

1. Add a section for the new version at the top of `CHANGELOG.md`, for example `## 1.0.1 (2026-12-01)`, summarising for players what is new (`### New`), fixed (`### Fixed`) and changed (`### Changed`). Commit it. This section, and only this one, becomes the changelog of the file on CurseForge (website and app). A release without it is refused.
2. Run `powershell -File scripts/release.ps1 -Version 1.0.1`. It sets the version in the TOC, commits, and tags.
3. Push the branch and the tag, or add `-Push` to the command.

A tag containing `beta` or `alpha` (for example `1.1.0-beta1`) becomes a beta or alpha file on CurseForge, and any other tag a release. Every push to `main` is a dry run, and so is a run started by hand from the Actions tab: it checks that CurseForge accepts the token, builds the zip, checks its contents and attaches it to the run, without uploading anything. The TOC must have its `## X-Curse-Project-ID:` line before a tag can upload.

To build a zip locally instead, run `powershell -File scripts/package.ps1`. It writes `dist/CinematicAzeroth-<version>.zip`, with `CinematicAzeroth` at the root of the archive and the licence inside it, like the workflow's zip.

The icon: `powershell -File scripts/make-icon.ps1 -Out curseforge/logo.png -Size 512` (CurseForge avatar) and `-Out CinematicAzeroth/media/icon.tga -Size 64` (in-game).
