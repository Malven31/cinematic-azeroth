# Cinematic Azeroth: features

Everything the addon does, option by option. The settings are in **Options > AddOns > Cinematic Azeroth**, also opened with `/cinema`. They are shared by all your characters.

## Cinematic mode

- **One key** turns it on: the whole interface disappears, nameplates included, and black letterbox bars slide in from the top and bottom of the screen. The same key, or **Escape**, brings everything back and the bars slide out.
- **Choosing the key:** on the options page, click the key button, then press a key or a mouse button (middle, 4 or 5), with Alt, Ctrl or Shift if you like. Escape cancels, right-click clears. It is also listed in Blizzard's Key Bindings, under Cinematic Azeroth. The mouse wheel can't be used: it can't be told apart from Blizzard's Toggle UI key.
- **Safe, and works in combat.** The addon doesn't hide the interface itself. Your key is redirected to Blizzard's own **Toggle UI** (the one on Alt+Z), so the game hides the interface exactly as it does for Alt+Z, and every window closes and reopens with Blizzard's own code. That is also why there is no slash command to toggle cinematic mode: only a key press can hide the interface safely.
- **Alt+Z stays as it was:** it hides the interface without bars. Tick **"Also add the bars when Blizzard's Toggle UI key hides the interface"** to get the bars with it too.
- Until you choose a key, the addon reminds you to type `/cinema` a few seconds after each login or `/reload`.

## What else goes

The interface always goes. These checkboxes, all on by default, choose what goes with it:

| Option | What it hides |
|---|---|
| Nameplates (Threat Plates included) | Every nameplate. Unticked, the addon brings them back right after the game hides them with the interface. |
| Names above heads (NPCs, players, pets) | The game's own names: yours, NPCs, players, pets, minions, critters. |
| Speech bubbles | Say, yell, party, raid and NPC bubbles. Unticked, the chat typing bar works in cinematic mode too (see below). |
| Combat numbers | The damage, healing and effect numbers shown on units. |
| Interaction icons (NPCs, fishing bobber) | The icon over the NPC or object you would interact with (vendor, trainer, flight master, mailbox...) and over the fishing bobber. Interacting still works. |

- These are switched off in the game's own settings and **put back exactly as they were** when cinematic mode ends, when you log out or reload, and, if the game crashed in cinematic mode, at your next login. A setting you changed yourself in the meantime is left as you set it.
- **During combat** the game doesn't let addons change the names, nameplate and interaction-icon settings. In a cinematic mode started during a fight, those go when the fight ends. With "Nameplates" ticked, the nameplates stay hidden throughout.
- **Better Fishing** switches the interaction icons back on at every cast. In cinematic mode the addon switches them off again each time, and Better Fishing's key still catches the fish. A cast already out when cinematic mode starts keeps its icon until it ends.

## Shown over the scene

| Option | Default | What shows |
|---|---|---|
| Interaction windows | On | The windows an NPC opens appear alone over the cinematic scene, at their usual place: NPC dialog and quests, loot, vendors, flight master, trainers, stable, bank, mail, auction house, books and trades, with their confirmation pop-ups (selling junk, bind on pickup, buying a stack...). |
| Bags (your bag key too) | On | Your bag keys open and close your bags over the scene, and vendors, the bank, the mailbox, trades and the auction house open them there too. The game refuses to open bags while the interface is hidden, so the addon opens them with Blizzard's own bag code. Closing the vendor closes the bags it opened, as usual. |
| Tooltips | Off | Item and spell tooltips, while an interaction window or the bags are open. Off, tooltips stay hidden in cinematic mode. |
| Quest marks (! and ?) | On | The marks over quest givers. They have no setting of their own: they go with the nameplates when the interface is hidden. So the addon brings that layer back and, with "Nameplates" ticked, switches the nameplates off in the game's settings instead (put back afterwards). Not possible during combat: then the marks come back when the fight ends. |

Everything moved over the scene goes back to its usual place when cinematic mode ends.

## Talking in cinematic mode

With **Speech bubbles** unticked, press Enter in cinematic mode: the chat typing bar fades in, you type and send as usual, and it fades out again. The bar stays invisible the rest of the time, and your bubbles show over the scene.

## Combat

- **Turn cinematic mode off when combat starts** (on): the interface, nameplates and names come back as a fight starts.
- **Come back to it after the fight** (on): when combat ended cinematic mode, it comes back 3 seconds after the fight. Not while you are typing (it waits up to 30 seconds), and not when you are dead. A new fight cancels it.

The game only lets a key press show or hide the interface safely, so for these two the addon does it itself, just before the fight locks the interface. If errors mentioning Cinematic Azeroth appear after a fight, or the chat stops sending, untick them and use your key.

## Flights

**Turn cinematic mode on during flights (flight master)** (on): taking a flight master's flight turns cinematic mode on, and landing turns it off again, unless you changed it with your key or Escape during the flight. Landing during a fight waits for the end of the fight. As for combat, the addon hides and shows the interface itself here.

If **DynamicCam** hides the interface during flights (its "Taxi" situation), turn one of the two off. With both on, Escape during a flight ends only the cinematic mode and the interface stays invisible until you land.

## Letterbox bars

- **Height of each bar**, from 0 to 25% of the screen height (12% by default).
- **Film formats:** the 2.39:1, 2.00:1 and 1.85:1 buttons set the height that leaves a picture of that shape on your screen. The page shows the shape you get.
- **Time for the bars to slide in or out**, from 0 to 2 seconds (0.6 by default), with a smooth start and stop.
- **Preview the bars** on the options page, or `/cinema test` for 3 seconds.
- The bars are drawn under the interface, so a preview never covers a window.

## Minimap mail envelope

When the interface is hidden, by cinematic mode, Alt+Z or anything else, the game hides the minimap's mail envelope and doesn't show it again until new mail arrives. The addon shows it again when the interface comes back, if mail is waiting.

## Commands

| Command | What it does |
|---|---|
| `/cinema` (or `/cinematicazeroth`) | Opens the options |
| `/cinema test` | Shows the bars for 3 seconds |
| `/cinema debug` | Saves what is on screen and your key's state, for a bug report |
| `/cinema watch` (`on`, `off`) | Diagnostics, off by default: a record of what is on screen 1 second into every cinematic mode, and a log of what shows or hides the buttons beside the chat. Remembered until you turn it off |
| `/cinema chat` | Saves the state of the buttons beside the chat |
| `/cinema help` | Lists the commands |

Records go into the addon's saved variables, `WTF\Account\<account>\SavedVariables\CinematicAzeroth.lua`, when you log out or type `/reload`. The file also keeps the last 40 cinematic-mode events, which helps with bug reports.
