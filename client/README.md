# Unciv VR – Godot client

A Godot 4.7 project that draws an Unciv game as a tabletop map and lets you play the basics
in VR or on the desktop. All the game rules run in the **unciv-bridge** (in the Unciv repo,
`bridge/`); this project only draws the game and sends commands to it.

## Running it
Open this folder in Godot (Import → select `project.godot`) and press **F5** (Run Project).

- **The bridge starts by itself.** If nothing is listening on port 8765, the client finds a JDK 17+
  (JDK 21 recommended), runs `gradlew :bridge:run` in `../unciv` (rebuilding the bridge if its
  code changed) and shuts it down when you quit (it saves the game as the autosave first). Its output goes to
  `logs/bridge.log`. A bridge you started by hand is used as-is and left running.
- **Left-over bridges are replaced.** If a bridge from an earlier session is still running old code (say the
  client was force-stopped from the editor), the client saves its game, stops it and starts a fresh one.
  A bridge the client started also quits by itself after three minutes with no client connected.
- **VR:** have your headset's OpenXR runtime running (SteamVR or Meta Quest Link) before pressing F5.
- **Desktop:** works with no headset. To skip the OpenXR check, add `--xr-mode off` to
  Project → Project Settings → Editor → Run → Main Run Args.

The client opens on the **main menu** (floating over the table): Continue (the autosave), Quick start
(the same setup as last time), New game (pick your civ, map and rules in three tabs) or Load game.
A bridge you started by hand that's already running a game is resumed straight away.
Saves and the autosave (written every turn, or as often as Settings > Game and saves says) live in
`~/.unciv-vr/SaveFiles`; Settings > Game and saves has Save game (you type the name; it starts as
"<civ> - turn <n>") and Main menu.

### Settings
The Settings button on the table (O on the desktop) opens the settings board, laid out like Unciv's Options:
**Look** (background, table, tiles and units as drop-down lists with what each one is, plus Unciv's visual hints - the
map overlays), **Gameplay** (Unciv's turn and unit-cycling options, how long the notification log is kept, how
other players' turns are shown), **Automation** (Unciv's automation options, and when automated units move),
**Controls** (desktop and VR), **Game and saves** (save, main menu, how often to autosave) and **About**
(versions, this game's rules, and the folders for your own tilesets, backgrounds and tables). In VR it floats
over the far half of the table and can be moved by its top strip like the other boards; Close, the Settings
button or (desktop) Esc puts it away.

## Controls
Everything can be done with the **right controller alone** (or the mouse on desktop): point at things and
pull the trigger. The left controller and the wrist card are optional shortcuts.

| | Desktop | VR |
|---|---|---|
| Select a unit | left-click it | point + right trigger: its card pops up above it (actions, improvements, Promote) |
| Move / attack | click a tile to aim (path, turns or expected damage show up), click it again to go | same, with point + right trigger |
| Move onto a tile one of your own units is on (a civilian and a military unit can share one, and a city holds more) | clicking that tile selects the unit on it, so **hold** the button on it instead: that aims, then click to go. "Move here" on the unit's card does the same, and when there's no room the aim says so (Swap places exchanges the two units) | same, holding the right trigger |
| Open a city | click it (with a unit selected it also aims the unit there; click again to march in) | point + right trigger: its card floats above the city |
| Empire overview (Unciv's stats and info screen) | E opens / closes it | always up, off to your right - turn your head to read it |
| City view | "City view" on the city's card; Esc or "Exit city" leaves | same; B or "Exit city" leaves |
| Rename a city / unit, name a save | "Rename" in the city view's header, on the unit card or in the overview's Units tab; type on the keyboard (or the on-screen one), Enter / Esc | the on-screen keyboard pops up on your left wrist (or floats in front of you if the left controller isn't tracked): point + right trigger on the keys, OK; B or Cancel closes it |
| Table buttons: Idle unit (left side); End turn, Recenter, Settings (right side); in the city view only a red Exit city | click | point + right trigger |
| Scroll a card | mouse wheel | point at it + right stick |
| Table height | – | either stick up / down (the right one only when not pointing at a card) |
| Rotate / scale table | right-drag orbit, wheel zoom, WASD / middle-drag pan | hold either grip + that stick: left / right rotates, up / down scales |
| Zoom the map (all the way out = whole map) | +/- or Ctrl + wheel | hold a trigger + that hand's stick up / down |
| Map overlays (Unciv's five: unit movements, tile yields, worked tiles, resources and improvements, improvement pictures) | click the round buttons beside the overview | point at one + right trigger |
| Slide the map (when zoomed in) | WASD, or click the overview | hold a grip and drag the map; or point at the overview at the far edge and pull the trigger |
| Shortcuts | Space end turn, F found city, Tab / Shift+Tab next / previous unit, N idle unit, T tech tree, P policies, G diplomacy, O settings, Esc close the big screen / deselect, R refresh | A end turn, B found city; X / Y next / previous unit, left stick click recenter; wrist card |

The right trigger clicks when you let go of it (so holding it to zoom, or to aim at a tile, doesn't also click).
### Turns, popups and decisions
Like Unciv's next-turn button, **End turn** first takes you to whatever still needs deciding, and its label says
what: a message to answer, a free great person to pick, a city with nothing to build, research, a policy, spies to
place, a pantheon or religion to found, a World Congress vote, or a unit still waiting for orders. With "Confirm next turn" on, it takes a second press.

After End turn, the moves and battles of the other players that you could see play back on the table, in
order, with the view gliding to fights outside it; **End turn** (now labelled **Skip**, or A / Space) skips the
rest. Settings > "Other players' turns" plays them normally, fast, or not at all. Your own moves and attacks
are animated too.

Unciv's popups (first contact, declarations of friendship, demands, trade requests, a city you've conquered,
wonders, golden ages, great people, victory and defeat...) come up as a card in the middle of the window, or
floating over the table (above the place they're about, if any) in VR, with Unciv's choices. They wait while
you're in the city view, typing, or picking a tile, and come back after a save and load. A conquered city offers
annex, puppet, raze or liberate, as Unciv would.

**Unit actions** are all of Unciv's (found, build, automate, explore, fortify, sleep, pillage, upgrade, promote,
escort, swap, connect road, disband...). Ones that need a tile (Swap, Connect road...) highlight the choices and
wait for a click on the map; Cancel on the card, B or Esc gives up, and so does picking another unit. Risky ones
(disband, pillage...) ask for a second click. A city with an enemy in range can
**Bombard** from its card.

The big screen also has **Religion** (Unciv's pantheon / religion pickers: beliefs per slot, symbol and name -
the name on the on-screen keyboard) and **Victory** (each victory's progress, rankings, the score / stats charts
over time, demographics; One more turn after a win). Its diplomacy tab opens a page per civ: city-states take
gifts of gold or an improvement, protection, tribute demands and marriage; major civs take declarations of
friendship, denouncements, demands, and trades, which they accept, decline or answer with a counter-offer you
can change and send back. The empire overview's **Espionage** tab moves spies and stages coups.

### The big screen
The **big screen** above them switches between the **technology tree** (click a tech to research it, or to
queue it and its prerequisites), **policies** (laid out like Unciv's policy screen with its symbols: click one to see its name and effects
along the bottom, then Adopt) and **diplomacy** (everyone you've met; Trade opens a deal screen where they
tell you straight away whether they'd accept; Declare war takes a second click to confirm; Offer peace).
Policy symbols are loaded from the Unciv repo's own images (`../unciv/android/Images.*`). Point at it and use the right stick to
scroll the wide tech tree. On the desktop it's a window: T / P / G open its tabs, Esc closes it.
It opens on its own when you need to pick research or can adopt a policy.

The board next to the overview shows your civilization's numbers and the tile you're pointing at.
All three can be moved (the big screen by the strip along its top): point, hold the trigger (or the left
mouse button for the overview) and drag;
in VR the right stick pushes it away / pulls it closer while you hold it. They stay put relative to the
table between sessions; Settings > Controls has "Put the boards back".
Unexplored tiles are hidden under clouds.

The **overview** stands at the far edge of the table in every game. The five round buttons down its right
side are Unciv's map overlays, with Unciv's own symbols and defaults (resources and improvement pictures on,
the rest off); your choice is remembered. The tech tree shows each tech's symbol and, underneath, the units,
buildings, wonders, resources and improvements it unlocks; click a tech for Unciv's full description and a
Research button along the bottom. Units carry their Unciv unit symbol in their civ's colours, cities their
nation's emblem, and the diplomacy cards, info board and new-game nation list use the nation emblems too.
All of these come from the Unciv repo's images (`../unciv/android/Images.*`); anything missing falls back to text.

The **empire overview** has all nine tabs of Unciv's Empire Overview, with Unciv's icons:
- **Cities**: every city's yields, population, production, WLTK / demands, garrison, defence, religion and city-wide
  resources; click a column header to sort (again to reverse), a city to open its city view, a garrison to select it.
- **Stats**: happiness, gold, science, culture and faith by source, great person points, score (and Unciv's gold-to-science
  slider when the ruleset has one).
- **Trades**: pending and current deals. **Units**: unit supply, and every unit (click to select it; the city to look
  there; the star to promote; the upgrade button - twice - to upgrade it anywhere).
- **Politics**: each civ's leader, era, policies, wonders and relations, or the diagram of who's at war / friends / allied.
- **Resources**: luxury and strategic resources by source, with unimproved and WLTK counts. **Religion**: religions,
  beliefs and founding numbers. **Wonders**: every wonder and natural wonder you know of, and where.
- **Notifications**: this turn's and earlier turns' messages; click one to go where it points.

The **city view** (from a city's card) does everything Unciv's city screen does. The table zooms onto the city
and shows each tile's yields with Unciv's worked / locked / not-worked symbols, gold prices on tiles the city
can buy, a purple outline on the next tile its borders will take, and shading over tiles it can't work.
Click a tile to work it or stop working it; click a priced tile twice to buy it; click another of your cities
to switch to it. The world boards make way for two city boards:
- **City** (left): the city's yields (click a stat symbol to focus on it), growth, borders, defence, resources and
  demands; citizen management (reset, avoid growth, every Unciv focus); specialists (+ / -, automatic or manual);
  great people; religion; its buildings; the clicked tile (lock, unlock, work, buy); raze / annex.
- **Production** (right): the queue (progress, move up / down, remove), everything it can build (or, with the
  toggle, can't build yet and why), and the picked item's Unciv description with Build now, Add to queue,
  Buy (gold or faith, where allowed) and Sell for buildings. Buying, selling and razing ask for a second click.

The city card keeps quick production picks (click to build next, with a gold price to buy).

Rings: cyan = reachable this turn, red = attackable, yellow = selected, white = under the pointer.
The glowing beam marks the selected unit.

## Command-line options
Put these after `--` (e.g. in Main Run Args: `-- --new-game --civ=Rome --map-size=Small`):
`--new-game`, `--civ=<nation>`, `--map-size=Tiny|Small|Medium|Large|Huge`, `--ai=<count>`,
`--load=<path to an Unciv save>`, `--port=<port>`, `--no-launch` (never start a bridge),
`--smoke-test` (scripted run that prints results and quits),
`--screenshot=<file.png>` (saves one frame after loading, then quits),
`--show=unit|aim|city|cityview|cityview-tile|overview-<tab>|overview-diagram|keyboard|research|promotion|settings|setup|setup-world|setup-rules|saves` (opens that card before the screenshot),
`--keyboard=wrist|float` (VR: where the on-screen keyboard goes, instead of deciding by whether the left controller is tracked),
`--lobby` (show the main menu even if the bridge is running a game), `--fake-xr` (VR layout without a
headset; `--fake-pitch=-12` tilts the fake head, `--fake-look=-60` turns it right before the screenshot), `--background=Studio|Mountains|Space|MountainKing|WebbDeepField` (or any background folder; not saved), `--table=Plain|OrnateOak` (or any table folder; not saved), `--tileset=LowPoly|classic` (or any tileset folder; not saved), `--unitset=tileset|none|<tileset folder>` (where unit models come from; not saved),
`--overlays=all` or e.g. `--overlays=movement,yields` (turns those map overlays on for this run, not saved).

For testing, start from the test save `--load=res://tests/saves/everything.json` (three cities, a full army, a
war party next to one of our cities, every civ met; see [tests/saves/README.md](tests/saves/README.md)) rather
than a new game. Scenarios (need a bridge started by hand with `--debug`, so use `--no-launch`): `--scenario=<name>` sets up
a situation from `scripts/dev_scenarios.gd` and plays through it the way a player would, printing `SCENARIO:`
lines (blockers, alerts, alerts_show, conquest, religion, great_person, victory, diplomacy, unit_actions, bombard,
espionage, **tiles** (reveals the map and saves pictures of the tileset zoomed out, at the usual size, on the
natural wonders and in the city view to `--shots=<folder>`, with how much it draws), **battles** (war with a
neighbour, enemy troops next to the capital, one of ours shoots, then End turn plays back the AI's attacks; steps
`staged_fight` and `unit_icons` follow it), **playback** (from the test save: End turn, and the AI's attacks play
back), **unit_death** (a war, an enemy hurt to one hit point, one shot: the unit dies and the map is rebuilt - its token is freed by the death animation, and looking it up afterwards used to stop the client dead), **stacking** (from the test save: moving onto a tile one of your own units is on - the hold, the click that follows, "Move here" on the card, and a tile with no room left - with a picture of each aim), **settings_board** (from the test save: every settings page as a picture, a drop-down opened and used,
toggles, and the number settings checked against the bridge), **surroundings** (from the test save: picks every background and table in Settings, saves a picture of
each to `--shots=<folder>`, and moves the table up, down and bigger to check its column and feet follow), **make_test_save** (with `--then=save_test_game`: rebuilds the test save), and **sequences**: inputs in orders nobody planned for - switching units halfway through an action,
double clicks, popups arriving while something else is open, save and load mid-decision - each printed as OK or
PROBLEM). `--then=step,step:arg` runs more of its steps afterwards (e.g. `--then=save_load,conquest_answer:puppet`).

Settings are saved in Godot's user folder (`user://settings.cfg`).

## Files
- `scripts/bridge_client.gd`: TCP + JSON-lines client with `await bridge.request(method, params)`
- `scripts/bridge_launcher.gd`: finds a JDK, starts and stops the bridge
- `scripts/action_menu.gd`: the card: unit actions and improvements, city production, research,
  and the main menu (lobby, new-game setup, saves)
- `scripts/world_panel.gd`: puts a 2D card on a quad in VR and feeds it laser-pointer clicks
- `scripts/backgrounds.gd`: the world around the table (sky, light, fog and scenery), read from a background folder
  (`backgrounds/<name>/` or `~/.unciv-vr/Backgrounds/<name>/`); see [backgrounds/README.md](backgrounds/README.md)
- `scripts/table_model.gd`: the table (top, stretchy column and feet), read from a table folder (`tables/<name>/` or
  `~/.unciv-vr/Tables/<name>/`); see [tables/README.md](tables/README.md)
- `scripts/settings_board.gd`: the settings board (pages of settings with drop-down lists, after Unciv's Options)
- `scripts/mod_folders.gd`: finding and loading those folders and their models (shared by backgrounds and tables)
- `scripts/hex_map.gd`: the terrain (from the tileset, or plain coloured hexes), borders, cities, units,
  highlights and picking; on big maps only a round window of it is drawn and slides under the table
- `scripts/tileset.gd`: loads a tileset (`tilesets/<name>/`, or `~/.unciv-vr/Tilesets/<name>/`) and picks the
  pieces for each tile the way Unciv picks tile images; see [tilesets/README.md](tilesets/README.md)
- `scripts/tileset_shaders.gd`: the animated materials (steam, geyser, smoke, lava, sparkle, shimmer, water)
- `scripts/unit_motion.gd`: units moving and fighting on the table (lunges, projectiles, hits, deaths), used for
  your own moves and attacks and to play back what the other players did that you could see
- `tilesets/LowPoly/`: the built-in low-poly tileset (`tileset.json` and its `.glb` pieces)
- `backgrounds/Studio/`, `Mountains/`, `Space/` and `tables/Plain/`, `OrnateOak/`: the built-in backgrounds and tables
  (a json file and `.glb` models each), made by `tools/make_surroundings.gd` (with `lowpoly_backgrounds.gd` and
  `tables.gd`)
- `tools/make_lowpoly_tileset.gd` (with `lowpoly_pieces.gd`, `lowpoly_wonders.gd`, `lowpoly_units.gd`): makes
  the low-poly pieces and unit models; `tools/tileset_preview.tscn` is the preview tool for tileset makers
  (every terrain, feature, wonder, resource, improvement and unit drawn with the game's map code, with a report
  of what each used and what's missing; see [tilesets/README.md](tilesets/README.md)); `tools/preview_tileset.gd`
  renders review sheets
- `scripts/minimap.gd`: the overview at the far edge of the table, with the map-overlay buttons
- `scripts/map_overlays.gd`: Unciv's five map overlays drawn on the table (movement arrows, yields, worked tiles,
  resource / improvement symbols, improvement models and roads)
- `scripts/big_screen.gd`: the big screen: tech tree, policies, diplomacy and trading, religion, victory
- `scripts/city_boards.gd`: the city view's two boards (the city, and its production)
- `scripts/overview_board.gd`: the empire overview (Unciv's Empire Overview tabs)
- `scripts/keyboard.gd`: the on-screen keyboard for names (cities, units, saves)
- `scripts/icons.gd`: loads Unciv's icons (policies, techs, stats, resources, units, nations...) from the Unciv repo
  and makes the round coloured badges
- `scripts/info_panel.gd`: the info board: civ numbers and the pointed-at tile, colour-coded like Unciv
- `scripts/main.gd`: game flow, table buttons, popups, desktop camera, XR rig, HUD and input
- `scripts/dev_scenarios.gd`: the `--scenario` test situations (developers only)

## Developer overrides
`override.cfg` next to `project.godot` (not committed) can change settings for local runs, e.g.
`[unciv_vr] dev_args="--smoke-test"` or `[xr] openxr/enabled=false`. Claude uses it to run
automated tests through the Godot MCP server, which can't pass command-line arguments.

## Licence and credits
The client's code is under the Mozilla Public License 2.0 (see [../LICENSE](../LICENSE)), like Unciv's. So are the
low-poly tileset's models and the backgrounds' and tables' models, which are our own (made by
`tools/make_lowpoly_tileset.gd` and `tools/make_surroundings.gd`).
The icons on the boards and the table are Unciv's own, loaded at runtime from `../unciv/android/Images.*` (not
copied into this repo). They are by many authors under CC BY / CC BY-SA / CC0 licences; see [../CREDITS.md](../CREDITS.md)
and Unciv's `docs/Credits.md`.
