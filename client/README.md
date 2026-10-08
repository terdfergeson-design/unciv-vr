# Unciv VR – Godot client (phase 0)

A Godot 4.7 project that draws an Unciv game as a tabletop map and lets you play the basics
in VR or on the desktop. All the game rules run in the **unciv-bridge** (in the Unciv repo,
`bridge/`); this project only draws the game and sends commands to it.

## Running it
1. Start the bridge: in the Unciv repo folder, run `gradlew.bat :bridge:run` and wait for
   `Unciv bridge listening on 127.0.0.1:8765`.
2. Open this folder in Godot (Import → select `project.godot`), then press **F5** (Run Project).
   - **VR:** start Quest Link first, with Meta Quest Link set as the active OpenXR runtime.
   - **Desktop:** works with no headset. To skip the OpenXR check, run with `--xr-mode off`
     (Project → Project Settings → Editor → Run → Main Run Args, or from the command line).

The client resumes the game that's running in the bridge, or starts a new one on a Tiny map.

## Controls
| | Desktop | VR |
|---|---|---|
| Select a unit / move it | left-click your unit, then a destination | point with right controller + trigger |
| End turn | Space / Enter | A |
| Found city (settler selected) | F | B |
| Next idle unit | N / Tab | X (left) |
| Look around | right-drag orbit, middle-drag or WASD pan, wheel zoom | left stick: rotate (x) / scale (y) table |
| Deselect / refresh | Esc / R | – / Y (left) refresh |

Cyan rings = where the selected unit can reach this turn, yellow = selected, white = hovered.

## Command-line options
Put these after `--` (e.g. in Main Run Args: `-- --new-game --civ=Rome --map-size=Small`):
`--new-game`, `--civ=<nation>`, `--map-size=Tiny|Small|Medium|Large|Huge`, `--ai=<count>`,
`--load=<path to an Unciv save>`, `--port=<port>`,
`--smoke-test` (scripted run that prints results and quits),
`--screenshot=<file.png>` (saves one frame after loading, then quits).

## Files
- `scripts/bridge_client.gd`: TCP + JSON-lines client with `await bridge.request(method, params)`
- `scripts/hex_map.gd`: hex terrain, trees, borders, cities, units, highlights and picking
- `scripts/main.gd`: game flow, desktop camera, XR rig, HUD and input
