# Unciv VR – Godot client

A Godot 4.7 project that draws an Unciv game as a tabletop map and lets you play the basics
in VR or on the desktop. All the game rules run in the **unciv-bridge** (in the Unciv repo,
`bridge/`); this project only draws the game and sends commands to it.

## Running it
Open this folder in Godot (Import → select `project.godot`) and press **F5** (Run Project).

- **The bridge starts by itself.** If nothing is listening on port 8765, the client finds a JDK 17+
  (JDK 21 recommended), runs `gradlew :bridge:run` in `../unciv` (rebuilding the bridge if its
  code changed) and shuts it down when you quit. Its output goes to `logs/bridge.log`.
  A bridge you started by hand is used as-is and left running.
- **VR:** have your headset's OpenXR runtime running (SteamVR or Meta Quest Link) before pressing F5.
- **Desktop:** works with no headset. To skip the OpenXR check, add `--xr-mode off` to
  Project → Project Settings → Editor → Run → Main Run Args.

The client resumes the game that's running in the bridge, or starts a new one on a Tiny map.

## Controls
Everything can be done with the **right controller alone** (or the mouse on desktop): point at things and
pull the trigger. The left controller and the wrist card are optional shortcuts.

| | Desktop | VR |
|---|---|---|
| Select a unit | left-click it | point + right trigger: its card pops up above it (actions, improvements, Promote) |
| Move / attack | click a tile to aim (path, turns or expected damage show up), click it again to go | same, with point + right trigger |
| Open a city | click it (with a unit selected it also aims the unit there; click again to march in) | point + right trigger: its card floats above the city |
| Table buttons: Idle unit (left side); End turn, Research, Recenter, Settings (right side) | click | point + right trigger |
| Scroll a card | mouse wheel | point at it + right stick |
| Table height | – | either stick up / down (the right one only when not pointing at a card) |
| Rotate / scale table | right-drag orbit, wheel zoom, WASD / middle-drag pan | hold either grip + that stick: left / right rotates, up / down scales |
| Shortcuts | Space end turn, F found city, Tab / Shift+Tab next / previous unit, N idle unit, T research, O settings, Esc deselect, R refresh | A end turn, B found city; X / Y next / previous unit, left stick click recenter; wrist card |

Rings: cyan = reachable this turn, red = attackable, yellow = selected, white = under the pointer.
The glowing beam marks the selected unit.

## Command-line options
Put these after `--` (e.g. in Main Run Args: `-- --new-game --civ=Rome --map-size=Small`):
`--new-game`, `--civ=<nation>`, `--map-size=Tiny|Small|Medium|Large|Huge`, `--ai=<count>`,
`--load=<path to an Unciv save>`, `--port=<port>`, `--no-launch` (never start a bridge),
`--smoke-test` (scripted run that prints results and quits),
`--screenshot=<file.png>` (saves one frame after loading, then quits),
`--show=unit|aim|city|research|promotion|settings` (opens that card before the screenshot), `--fake-xr` (VR layout without a
headset; `--fake-pitch=-12` tilts the fake head), `--background=studio|mountains|space` (not saved).

Settings are saved in Godot's user folder (`user://settings.cfg`).

## Files
- `scripts/bridge_client.gd`: TCP + JSON-lines client with `await bridge.request(method, params)`
- `scripts/bridge_launcher.gd`: finds a JDK, starts and stops the bridge
- `scripts/action_menu.gd`: the card: unit actions and improvements, city production, research
- `scripts/world_panel.gd`: puts a 2D card on a quad in VR and feeds it laser-pointer clicks
- `scripts/backgrounds.gd`: sky, lighting and scenery (studio, low-poly mountains, space), all generated in code
- `scripts/hex_map.gd`: hex terrain, trees, borders, cities, units, highlights and picking
- `scripts/main.gd`: game flow, table buttons, popups, desktop camera, XR rig, HUD and input

## Developer overrides
`override.cfg` next to `project.godot` (not committed) can change settings for local runs, e.g.
`[unciv_vr] dev_args="--smoke-test"` or `[xr] openxr/enabled=false`. Claude uses it to run
automated tests through the Godot MCP server, which can't pass command-line arguments.
