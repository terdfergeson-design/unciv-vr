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
| | Desktop | VR |
|---|---|---|
| Select a unit | left-click it | point with the right controller + trigger |
| Move | click a cyan tile (or any tile further away) | point + trigger |
| Attack | click a red-ringed tile (hover it first for the expected damage) | point + trigger |
| Unit actions, worker improvements, next unit, end turn | the unit card, top right | the unit card on your left wrist: point at a button + trigger |
| End turn / found city / next unit | Space / F / N | A / B / X (left) |
| Look around | right-drag orbit, middle-drag or WASD pan, wheel zoom | left stick: rotate (x) / scale (y) the table |
| Deselect / refresh | Esc / R | – / Y (left) |

Rings: cyan = reachable this turn, red = attackable, yellow = selected, white = under the pointer.

## Command-line options
Put these after `--` (e.g. in Main Run Args: `-- --new-game --civ=Rome --map-size=Small`):
`--new-game`, `--civ=<nation>`, `--map-size=Tiny|Small|Medium|Large|Huge`, `--ai=<count>`,
`--load=<path to an Unciv save>`, `--port=<port>`, `--no-launch` (never start a bridge),
`--smoke-test` (scripted run that prints results and quits),
`--screenshot=<file.png>` (saves one frame after loading, then quits).

## Files
- `scripts/bridge_client.gd`: TCP + JSON-lines client with `await bridge.request(method, params)`
- `scripts/bridge_launcher.gd`: finds a JDK, starts and stops the bridge
- `scripts/action_menu.gd`: the unit card (actions, improvements, turn buttons)
- `scripts/hex_map.gd`: hex terrain, trees, borders, cities, units, highlights and picking
- `scripts/main.gd`: game flow, desktop camera, XR rig, HUD and input

## Developer overrides
`override.cfg` next to `project.godot` (not committed) can change settings for local runs, e.g.
`[unciv_vr] dev_args="--smoke-test"` or `[xr] openxr/enabled=false`. Claude uses it to run
automated tests through the Godot MCP server, which can't pass command-line arguments.
