# Tilesets

The map on the table is drawn with a **tileset**: a folder of 3D models ("pieces") plus a small
config file, modelled on [Unciv's tilesets](https://github.com/yairm210/Unciv/blob/master/docs/Modders/Creating-a-custom-tileset.md).
Pick one in **Settings > Tiles**. "Plain coloured hexes" draws the old flat prisms in Unciv's terrain colours.

Unciv VR comes with one tileset, **Low poly** (`LowPoly/`). Its pieces are made by a script,
`tools/make_lowpoly_tileset.gd`, which saves them in the same format you'd use for your own set.

## Where tilesets live

| Folder | What's there |
| --- | --- |
| `client/tilesets/<Name>/` | The built-in sets |
| `~/.unciv-vr/Tilesets/<Name>/` (Windows: `C:\Users\<you>\.unciv-vr\Tilesets\<Name>\`) | Your own and downloaded ones, next to the saved games |

A tileset folder looks like this:

```
MyTileset/
  tileset.json          the config (only "name" is required)
  pieces/
    Grassland.glb       one model per piece, named like Unciv's tile images
    Grassland2.glb      a variant
    Grassland-Far.glb   a simpler stand-in, used when much of the map is on the table
    Grassland Hill.glb
    Forest.glb
    Mount Fuji.glb
    ...
```

Models are read when the game runs, so there's nothing to import: drop a folder in, open Settings, pick it.
Pieces can be `.glb` / `.gltf` (export them from Blender), or Godot `.tscn` / `.scn` scenes for anything a
model can't do (particles, lights, scripts). Scenes are placed once per tile, so keep them for rare tiles.

## Making pieces

- **Units:** map units. A hex has a circumradius of 1; tiles are drawn with their corners at **0.97** so
  there's a hairline gap between them.
- **Orientation:** flat-topped hexes with the first corner on **+X**, **Y up**, origin at the hex centre
  at table level. In Blender (Z up, -Y forward) the glTF exporter converts this for you: model with a
  corner on +X and the hex lying on the ground plane.
- **Height:** land tiles in Low poly have their top edge at **0.15** and water at 0.03-0.07, so
  neighbouring tiles always meet. Anything inside the edge can rise or dip freely.
- **Keep the middle clear:** unit tokens stand about 0.3 from the centre. Put trees, rocks and
  resources mostly towards the rim.
- **Colour:** Low poly uses vertex colours, one flat colour per face. Textures work too.
- **Materials with special names are animated** (the name may also *end* with one of these):

  | Material | What it does |
  | --- | --- |
  | `Water` | normal water, but its shine fades on tiles that are out of sight |
  | `Steam` | puffs rise and grow in a loop |
  | `Geyser` | like Steam, and erupts high every 14 seconds |
  | `Smoke` | slow, dark puffs that billow up and drift with the wind |
  | `Lava` | glows, with its brightness rolling across the surface |
  | `Sparkle` | glints that twinkle on and off |
  | `Shimmer` | glowing water, gently rippling |

  The puff materials (Steam, Geyser, Smoke) move each puff as a whole, so each puff's vertices must carry
  the puff's centre: **UV** = (centre x, centre z), **UV2** = (centre y, height of the whole plume), and
  the **vertex colour's alpha** = how far up the plume the puff starts (0 at the bottom, just under 1 at
  the top). `tools/lowpoly_wonders.gd` (`_steam`) shows how.

## Units

Unit models go in `pieces/Units/`, named after the unit (`Swordsman.glb`). As in Unciv, the game looks for
`<unit>-<style>-<era>`, `<unit>-<era>`, `<unit>-<style>`, then `<unit>`; then the unit it replaces (so a civ's
unique unit, like the Legion, shows as a Swordsman until it has a model of its own); then its unit type
(`Sword`, `Mounted`, `Melee Water`...); then the fallback tileset; and in the end a round token with the unit's
icon. `Embarked` is the boat land units ride in at sea. (Era and nation styles aren't passed yet; the names are
reserved.)

- **Size:** origin on the ground at the middle of the unit's spot, about 0.25 map units across; `unitScale`
  in tileset.json draws them bigger (Low poly: 1.6). Land troops in Low poly are squads of three (two riders).
- **Facing:** the model faces **+Z**. The game turns it towards where it moves and what it fights.
- **Civ colours:** surfaces with materials named `CivOuter` / `CivInner` (or ending with those names) take
  the owner's outer / inner colour, multiplied by their vertex colours (Unciv's `-1` / `-2` tinted layers).
- **Aircraft** are modelled in the air (Low poly: 0.3 above the ground).
- **Battle and movement:** every model gets the game's generic motion - lunging, firing a projectile picked by
  the unit's `attackSound`, shaking when hit, toppling or sinking when it dies, hopping from tile to tile. A
  `.glb` or scene with an AnimationPlayer can add clips named `attack`, `hit`, `die` and `move`, which play
  at those moments.
- A small version of the unit's Unciv icon floats above it (the "unit icons" button beside the overview
  turns those off); the health bar shows whenever it's hurt.

## How a tile picks its pieces

Each tile is drawn as a stack of pieces, looked up by name the way Unciv looks up tile images:

1. **The whole tile:** if `ruleVariants` has an entry for `Base+Features+Resource+Improvement`
   (e.g. `"Grassland+Forest+Deer+Camp"`), exactly those pieces are drawn.
2. **Terrain:**
   - A **natural wonder** is a whole tile of its own: the piece named after the wonder
     (`Mount Fuji`), else `NaturalWonder` (Unciv's "summary image" idea, for wonders from mods).
     A `ruleVariants` entry named after the wonder can list layers instead.
   - Otherwise `ruleVariants["Base+Feature+..."]`, else a piece named `Base+Feature+...`, else the
     base terrain's piece followed by one piece per feature (`Plains`, then `Forest`).
3. **Rivers:** `River-Bottom`, `River-BottomLeft`, `River-BottomRight`, on whichever sides have one.
4. **Resource and improvement:** `ruleVariants["Resource+Improvement"]`, else a piece named
   `Resource+Improvement`, else the resource's piece and then the improvement's. For the improvement,
   `<name>-Pillaged` and `<name>-<era>` (e.g. `Farm-Medieval era`) are tried first.
   Improvement pieces follow the "improvement pictures" map overlay toggle; improvements the set has
   no piece for get the game's own little models.

- **Variants:** pieces named `X2`, `X3`... are variants of `X`. Each tile picks one variant number for all
  its pieces (each piece uses that number modulo how many variants it has), so a `Grassland Hill2` and a
  `HillForest2` made for the same hill shape always go together.
- **Rotation:** with `randomRotation` on, each tile's terrain pieces are turned by a random multiple of
  60°, so repeated tiles don't look stamped. Rivers, resources and improvements never turn.
- **Far versions:** with more than 900 tiles on the table, `X-Far` is used instead of `X` when it exists.
- **Missing pieces** come from `fallbackTileSet`. A tile whose base terrain has no piece at all is drawn
  as a plain coloured hex, so tilesets keep working with mods that add new terrains.

## tileset.json

Unciv-style json; `//` comments are allowed. Everything but `name` is optional.

```json
{
	"name": "My tileset",
	"description": "Shown nowhere yet, but good to have",
	"author": "you",
	"fallbackTileSet": "LowPoly",
	"randomRotation": true,
	"tileScale": 1.0,
	"tileScales": {"Mount Fuji": 1.1},
	"heights": {"Land": 0.15, "Water": 0.05, "Hill": 0.36, "Mountain": 0.7, "NaturalWonder": 0.5},
	"ruleVariants": {
		"Grassland+Hill": ["Grassland Hill"],
		"Tundra+Forest": ["Tundra", "ForestT"]
	}
}
```

| Key | Meaning |
| --- | --- |
| `name` | Shown in Settings |
| `fallbackTileSet` | Folder name of another tileset to take missing pieces from, or `null` |
| `randomRotation` | Turn terrain pieces randomly in 60° steps (default `true`) |
| `unitScale` | How much bigger than modelled unit models are drawn (default 1) |
| `tileScale`, `tileScales` | Scale every piece, or particular ones (Unciv's settings of the same names) |
| `edgeHeights` | How high each tile's rim is, where territory borders lie: by natural wonder, base terrain, then `Land` / `Water` |
| `heights` | Where units and cities stand on a tile, in map units: by natural wonder name (then `NaturalWonder`), feature (the last one listed wins), base terrain, then `Land` / `Water` |
| `ruleVariants` | Which pieces to stack, in order, for a particular combination (see above) |

## Trying a tileset quickly

`tools/preview_tileset.gd` renders every tile type, the wonders, or a sample map to pictures:

```
godot --path client -s tools/preview_tileset.gd -- <TilesetFolder> <output folder>
godot --path client -s tools/preview_tileset.gd -- <TilesetFolder> <output folder> wonders
godot --path client -s tools/preview_tileset.gd -- <TilesetFolder> <output folder> anim "Old Faithful"
godot --path client -s tools/preview_tileset.gd -- <TilesetFolder> <output folder> units
godot --path client -s tools/preview_tileset.gd -- <TilesetFolder> <output folder> battle
```

The Low poly set is rebuilt with:

```
godot --headless --path client -s tools/make_lowpoly_tileset.gd
```

## Licence

The Low poly pieces and units, and the scripts that make them are part of Unciv VR, under the Mozilla Public
License 2.0, like the rest of the project.
