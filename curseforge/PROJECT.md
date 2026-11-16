# CurseForge checklist

Everything the CurseForge project and file upload ask for, ready to paste.

## Before the first upload

1. **Test in the game** after a full restart (the icon and the TOC are new), then check the BugSack for errors:
   - The addon list and the addon compartment show the new icon.
   - The key turns cinematic mode on and off, the bars slide in and out, and Escape brings the interface back.
   - Names, speech bubbles, combat numbers and interaction icons go, and come back afterwards.
   - A vendor's window and the bags open over the scene. Selling and buying work.
   - Quest marks show over quest givers.
   - A fight started in cinematic mode brings the interface back, and cinematic mode returns 3 seconds after it. Chat still sends afterwards.
   - A flight master's flight turns cinematic mode on, and landing turns it off.
   - `/cinema watch` turns the diagnostics on and off, and `/cinema debug` saves a snapshot.
2. **Repository:** `github.com/Malven31/cinematic-azeroth`.
3. **Visibility:** the repository is public (checked 2026-11-16), so the Source and Issues links below and images loaded in the description work. Keep it public.
4. **Logo:** [logo.png](logo.png) (512×512, the addon's own). The in-game icon `CinematicAzeroth/media/icon.tga` (64×64) is the same picture. `scripts/make-icon.ps1` draws both.
5. **Screenshots and animation:** see [gallery/README.md](gallery/README.md).

## Moderation rules to keep in mind

From CurseForge's moderation policies (<https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies>):

- The name, logo, summary and description are the addon's own.
- Outside links, such as the GitHub repository and any donation link, go at the very bottom of the description, small.
- Keep a channel for bug reports open: the project's comments, plus GitHub Issues once the repository is public.
- If CurseForge asks for changes or rejects the project, fix it and reply or appeal. Never delete the project or file to upload it again.

## Create the project

| Field | Value |
|---|---|
| Game | World of Warcraft |
| Project type | Addons |
| Name | Cinematic Azeroth |
| Summary | One key hides the interface and nameplates and slides in cinematic letterbox bars. Safe in combat, made for Forever. |
| Description | [description.md](description.md) |
| Category | HUDs, plus Roleplay or Miscellaneous if offered |
| Licence | MIT License |
| Logo | [logo.png](logo.png) |
| Source | `https://github.com/Malven31/cinematic-azeroth` |
| Issues | `https://github.com/Malven31/cinematic-azeroth/issues` |

If the description editor has no Markdown mode, open `description.md` in a Markdown preview (VS Code: Ctrl+Shift+V) and copy the rendered text. The formatting comes along.

## Once the project exists

The project ID is in the "About Project" box of the project page (a number, not the URL slug).

1. Add `## X-Curse-Project-ID: <id>` to `CinematicAzeroth/CinematicAzeroth.toc`. Without it, the workflow refuses tags and `scripts/release.ps1` refuses to tag.
2. Uncomment the download badge at the top of `description.md` and `README.md`, with the ID (and the project's URL slug in the README link). It reads "downloads: not found" until CurseForge's public API lists the project, presumably after moderation.

## Automatic packaging (set up once)

Files are packaged and uploaded by GitHub when a version tag is pushed: `.github/workflows/release.yml` runs the BigWigs packager, following `.pkgmeta`.

- **The zip** contains `CinematicAzeroth` at its root, with the licence inside it. `.pkgmeta` moves the folder there and leaves out the docs, `curseforge/` and `scripts/`.
- **The project** comes from `## X-Curse-Project-ID:` in `CinematicAzeroth/CinematicAzeroth.toc`. A tag without it fails at the "Check the CurseForge project ID" step, because the packager would otherwise skip the upload without a word. A dry run only warns.
- **The game version** comes from `## Interface: 16001`, which the packager knows as Forever.
- **The changelog** of each file is that version's section of `CHANGELOG.md`, in Markdown. `scripts/release-notes.sh` extracts it into `RELEASE_NOTES.md` before packaging. The workflow fails if the section is missing or lists nothing.
- **The token is checked on every run**, with CurseForge itself and without uploading anything. A missing, wrong or revoked token fails the run.
- **Every push to `main` is a dry run.** It checks the token, builds the zip, checks it (`CinematicAzeroth/` alone at the root, with its TOC, key bindings, icon and licence, and no repository files) and attaches it to the run. Nothing is uploaded: only a pushed tag uploads.
- **File name and display name:** `CinematicAzeroth-<version>`.
- **The release type** comes from the tag: one containing `beta` or `alpha` makes a beta or alpha file, any other a release.

To set it up:

1. Create a CurseForge API token at <https://authors.curseforge.com/#/settings/api-tokens>, or reuse the one made for Kong UI Hider: a token belongs to the CurseForge account, not to a project.
2. On GitHub, open this repository's Settings > Secrets and variables > Actions > New repository secret. Name it `CF_API_TOKEN` and paste the token. Secrets are per repository: Kong UI Hider's doesn't reach this one.
3. **Leave CurseForge's own "package on tagged commit" option off.** With both on, every tag would be uploaded twice.
4. **Dry run:** push to `main`, or on GitHub open Actions > Package > Run workflow. A green run means CurseForge accepts the token and the zip holds exactly what players should get. Nothing is uploaded.

## Releasing a version

1. Add a section at the top of `CHANGELOG.md`, for example `## 1.0.1 (2026-12-01)`, with `- ` entries under `### New`, `### Fixed` and `### Changed`: a player-facing summary of the new features and fixed bugs. Commit it.
2. Run `powershell -File scripts/release.ps1 -Version 1.0.1`. It checks that the working tree is clean, the TOC has the project ID and the changelog has the section, sets `## Version:` in the TOC, commits, and tags.
3. Push `main` and the tag (Sourcetree: Push with "Push all tags" ticked, or add `-Push` to the command).
4. Follow the upload in GitHub's Actions tab, then check the new file on CurseForge: game version Forever 1.60.1, release type, changelog.

**First version:** publish it as a beta, `scripts/release.ps1 -Version 1.0.0-beta1` (it uses the `## 1.0.0` changelog section). Once it is confirmed in-game, release `1.0.0`.

If an automatic upload fails, build the zip by hand with `powershell -File scripts/package.ps1` and upload `dist/CinematicAzeroth-<version>.zip` on the project's Files page: game version Forever 1.60.1, changelog type Markdown, the text from `bash scripts/release-notes.sh <version>`.
