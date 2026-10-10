# Backgrounds

Around the table is a **background**: the sky, the light, fog, and the scenery. Each one is a folder with a
`background.json` and (usually) a scenery model. Pick one in **Settings > Background**.

Unciv VR comes with five: **Studio** (a plain dark room), **Mountains and clouds** (the default), **Floating
in space**, **In the Hall of the Mountain King** (a troll king's cavern, lit by braziers and magma) and **Webb
Deep Field** (the table adrift among the galaxies of the James Webb telescope's first deep field). The first
three are made by `tools/make_surroundings.gd` (with `tools/lowpoly_backgrounds.gd`) and the cavern by
`tools/make_mountain_king.gd`, which save them in the same format you'd use for your own.

## Where backgrounds live

| Folder | What's there |
| --- | --- |
| `client/backgrounds/<Name>/` | The built-in backgrounds |
| `~/.unciv-vr/Backgrounds/<Name>/` (Windows: `C:\Users\<you>\.unciv-vr\Backgrounds\<Name>\`) | Your own and downloaded ones, next to the saved games |

```
MyBackground/
  background.json   the sky, light and fog (only "name" is required)
  scenery.glb       everything around the table (optional)
  sky.hdr           a sky picture, if you use one (optional)
```

Files are read when the game runs, so there's nothing to import: drop a folder in, open Settings, pick it.

## The scenery

- One model (`.glb` / `.gltf`, exported from Blender, or a Godot `.tscn` / `.scn` scene for particles, lights or
  scripts), in **metres**, **Y up**, with the **floor at y = 0** under the middle of the table. You stand on the +Z
  side of the table, about a metre from its middle; the table top is 0.8 to 1.2 m up.
- Keep the area within about 2 m of the middle clear, so you don't stand inside a tree.
- Shadows are only drawn within about 20 m.
- Materials named like the tileset's animated ones (`Water`, `Lava`, `Smoke`, `Steam`, `Sparkle`...; see
  [tilesets/README.md](../tilesets/README.md)) are animated the same way.
- **Spinning:** name a node in `spin` and it turns slowly about the middle (clouds drifting, stars wheeling).

## background.json

Unciv-style json; `//` comments are allowed. Everything but `name` is optional. Colours are `[red, green, blue]`
from 0 to 255 (as in Unciv's nation colours), or `"#rrggbb"`.

```json
{
	"name": "My background",
	"author": "you",
	"description": "Shown in Settings under its name",
	"sky": {"top": [82, 133, 209], "horizon": [199, 219, 237], "groundHorizon": [153, 173, 153], "groundBottom": [64, 84, 56]},
	"ambient": {"energy": 1.0},
	"fog": {"color": [191, 212, 230], "density": 0.004},
	"sun": {"pitch": -40, "yaw": 140, "color": [255, 245, 224], "energy": 1.3},
	"floor": true,
	"scenery": "scenery",
	"spin": {"Clouds": 0.57}
}
```

| Key | Meaning |
| --- | --- |
| `name` | Shown in Settings |
| `description`, `author` | Shown in Settings, under the name and in the list |
| `sky` | One of: `{"color": c}` a plain colour; `{"panorama": "sky.hdr"}` a picture wrapped all the way round (equirectangular `.png`, `.jpg`, `.hdr` or `.exr`; `"energy"` brightens it); or a gradient `{"top", "horizon", "groundHorizon", "groundBottom", "sunSize"}` (Godot's procedural sky, which also draws the sun) |
| `ambient` | The light that comes from everywhere: `{"color": c, "energy": 1}`. Without a colour it comes from the sky (gradient and picture skies only) |
| `fog` | `{"color": c, "density": 0.004}`; leave it out for none |
| `sun` | `{"pitch": degrees (negative shines down), "yaw": degrees (0 shines from behind you towards the table), "color": c, "energy": 1.4, "shadows": true}`; energy 0 turns it off |
| `floor` | `false` when there's nothing to stand on: the table's column and feet are hidden |
| `scenery` | The model file, with or without its extension (default `scenery`) |
| `spin` | Nodes in the scenery that turn about the middle: node name -> degrees per second |

## Trying it

`godot --path client -- --background=MyBackground` starts the game with it (not saved). The tileset preview tool's
background menu lists yours too, and the `surroundings` test scenario (see the client README) takes a picture of
every background.

## Licence

The built-in backgrounds and the scripts that make them are part of Unciv VR, under the Mozilla Public License
2.0, like the rest of the project.
