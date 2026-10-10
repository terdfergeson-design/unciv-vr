# Tables

The map lies on a **table**: a folder with a `table.json` and up to three models. Pick one in **Settings > Table**.

Unciv VR comes with two: **Plain wood** (`Plain/`, the original dark round table) and **Ornate oak**, the default
(`OrnateOak/`). Their models are made by a script, `tools/make_surroundings.gd` (with `tools/tables.gd`), which
saves them in the same format you'd use for your own table.

## Where tables live

| Folder | What's there |
| --- | --- |
| `client/tables/<Name>/` | The built-in tables |
| `~/.unciv-vr/Tables/<Name>/` (Windows: `C:\Users\<you>\.unciv-vr\Tables\<Name>\`) | Your own and downloaded ones, next to the saved games |

```
MyTable/
  table.json   the config (only "name" is required)
  top.glb      the table top
  column.glb   the stretchy middle (optional)
  base.glb     the feet (optional)
```

Models are read when the game runs, so there's nothing to import: drop a folder in, open Settings, pick it.
They can be `.glb` / `.gltf` (export them from Blender) or Godot `.tscn` / `.scn` scenes (for lights, particles or
scripts).

## The three parts

In VR you can raise, lower, turn and scale the table, so it's built from parts that move differently:

| Part | Moves with | Modelled |
| --- | --- | --- |
| **top** | the map: it turns and scales with it | in metres, centred on the middle of the map; the play surface is at **y = 0** |
| **base** | stands on the floor under the table, turns and scales with it | from the floor (y = 0) up to `baseHeight` |
| **column** | fills the gap between the two, stretched to fit | **1 m tall** (y = 0 to 1), and stretched up or down |

- **The play surface:** the map is a round window **0.7 m** across from the middle (its radius). The buttons sit
  on a ring from 0.74 to 0.83 m, so keep the top flat out to about **0.84 m**. Past that it can do anything;
  the built-in tops end at 0.84 (Plain) and 0.9 (Ornate oak). Don't put anything above y = 0 inside 0.84 m.
- **Up is +Y; you sit on the +Z side.** Round tables don't mind, but a square one or one with a front should face +Z.
- **The column** is stretched, so anything that runs up and down it (flutes, a plain shaft) looks right at any
  height; rings and bulges belong in the top or the base instead. A table with no column (or no base) is fine:
  nothing is drawn in its place.
- **The base** is squashed when the table is lower than the base and top are tall together; below that the
  column and base hide. When the background has no floor (Space), only the top shows.
- **Scale:** the game scales all three parts by the table's scale (grip + stick in VR), the column and base only
  as far as they fit under the top.

## table.json

Unciv-style json; `//` comments are allowed. Everything but `name` is optional.

```json
{
	"name": "My table",
	"author": "you",
	"description": "Shown in Settings under its name",
	"top": "top",
	"column": "column",
	"base": "base",
	"columnTop": -0.226,
	"baseHeight": 0.32,
	"specular": 0.2
}
```

| Key | Meaning |
| --- | --- |
| `name` | Shown in Settings |
| `description`, `author` | Shown in Settings, under the name and in the list |
| `top`, `column`, `base` | The model files (with or without the extension; defaults `top`, `column`, `base`) |
| `columnTop` | Where the column meets the top: metres below the play surface, so negative (default -0.04) |
| `baseHeight` | How tall the base is: the column starts this high above the floor (default 0) |
| `specular` | How much every surface reflects its surroundings, 0 to 1 (Godot's default 0.5 makes wood look wet; glTF can't say this itself) |

## Making a table

- **Materials:** anything glTF can do: colours, textures (base colour, normal, roughness maps), vertex colours
  (multiplied with the colour, handy for darkening carving). Textures get mipmaps when they're loaded.
- **Size:** keep a model under a few MB; the built-in Ornate oak is about 3.5 MB with its wood pictures.
- **Trying it:** `godot --path client -- --table=MyTable` starts the game with it (not saved), and the
  `surroundings` test scenario (see the client README) takes a picture of every table and checks the column and
  feet follow the table up and down.
- **Ornate oak**, if you want to see how one is built: `tools/tables.gd` turns profiles on a lathe (the top's
  edge, the urns), sweeps a shape along a curve (the scroll feet), and paints the oak boards' grain in code.

## Licence

The built-in tables and the scripts that make them are part of Unciv VR, under the Mozilla Public License 2.0,
like the rest of the project.
