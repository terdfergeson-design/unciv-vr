# Converting Garry's Mod & Source Engine Maps to Backgrounds

Unciv VR includes a dedicated conversion pipeline that transforms Valve Source Engine maps (`.bsp`), Garry's Mod Addon packages (`.gma`), and compressed map archives (`.zip`) into native 3D backgrounds.

This guide explains how to convert custom environments, position the game table, calibrate lighting, and manage map packages for local use.

---

## 1. Overview

Each background in Unciv VR is a self-contained directory containing:
- **`scenery.glb`**: A glTF 2.0 binary mesh containing the 3D world geometry, displacement terrain, and embedded PBR textures.
- **`background.json`**: Configuration for sky gradients/panoramas, directional sunlight, ambient illumination, and atmospheric fog.

```
~/.unciv-vr/Backgrounds/MyCustomMap/
  ├── background.json
  └── scenery.glb
```

The converter extracts world geometry, parses material descriptors, decodes Source textures, calculates lighting parameters from map entities, and outputs an optimized background ready for immediate in-game selection.

---

## 2. Supported Formats

| Format | File Extension | Description | Archive Handling |
| :--- | :--- | :--- | :--- |
| **Compressed Archive** | `.zip` | Standard compressed archive containing `.bsp` maps, loose materials, or embedded addons. | Automatically extracted; searches for `.bsp` and `.gma` files. |
| **Garry's Mod Addon** | `.gma` | Official Steam Workshop container format (`GMAD`). Bundles maps, custom textures, models, and scripts. | Unpacked natively without requiring Garry's Mod or external extraction utilities. |
| **Source Engine Map** | `.bsp` | Compiled Valve map file (VBSP versions 19, 20, 21). | Parsed directly; extracts world brushes, displacements, entities, and embedded pakfiles. |

---

## 3. Prerequisites

The conversion tool requires **Python 3.8+** with `numpy` and `Pillow`:

```bash
pip install numpy pillow
```

No external Source SDK tools, Garry's Mod installation, or Steam accounts are required to run the converter.

---

## 4. Storage & Copyright Policy

To protect project licensing and respect third-party intellectual property:

1. **Local Mod Directory by Default:**
   All converted backgrounds default to your private user mod folder:
   - **Windows:** `%USERPROFILE%\.unciv-vr\Backgrounds\<BackgroundName>\`
   - **Linux / macOS:** `~/.unciv-vr/Backgrounds/<BackgroundName>/`
2. **Never Commit Third-Party Maps:**
   Third-party `.bsp`, `.gma`, `.vtf`, `.vmt`, and `.zip` files, along with converted map folders, are ignored by `.gitignore` and must not be committed to the public Git repository.
3. **Addons are strangers' files:**
   A `.gma` or `.zip` from the Workshop can name its files anything, including paths like `../../somewhere`. The
   converter unpacks them into a temporary folder and skips any file whose path would land outside it, so an addon
   can't write into the rest of your computer.
4. **Automatic Discovery:**
   Unciv VR automatically discovers any background folder located in `~/.unciv-vr/Backgrounds/` when the game launches. It appears directly under **Settings > Background**.

---

## 5. Usage & Examples

The converter is located at `client/tools/convert_gmod_map.py` (with an optional Godot script wrapper at `client/tools/convert_gmod_map.gd`).

### Basic Conversion from `.zip`
```bash
py client/tools/convert_gmod_map.py "path/to/map_archive.zip" --name "My Map"
```

### Basic Conversion from `.gma`
```bash
py client/tools/convert_gmod_map.py "path/to/addon.gma" --name "Custom Arena"
```

### Basic Conversion from `.bsp`
```bash
py client/tools/convert_gmod_map.py "path/to/map.bsp" --name "Warehouse"
```

### Running via the Godot CLI
```bash
godot --headless --path client -s tools/convert_gmod_map.gd -- "path/to/map_archive.zip" --name "My Map"
```

---

## 6. Table Positioning & Calibration

In a background's own space (see [README.md](README.md)), the floor is at $Y=0$ under the middle of the table, which is above the origin $(X=0, Z=0)$; the table top is 0.8 to 1.2 m up, and you stand about a metre from its middle on the $+Z$ side, facing $-Z$. Keep the area within about 2 m of the middle clear, so you don't stand inside a wall.

Source Engine maps use Hammer Units where $1\text{ meter} \approx 39.37\text{ Hammer units}$ (scale factor $0.0254$), and map coordinates can be thousands of units away from $(0, 0, 0)$. The converter provides several strategies to align the table within the environment.

### Strategy A: Center / Basin Mode (`--center`)
Automatically calculates the horizontal center of the map's geometry, samples the lowest walkable floor surface, and positions the table in the middle of the area. Ideal for symmetrical arenas, skateparks, and open courtyards:

```bash
py client/tools/convert_gmod_map.py "map_archive.zip" --name "Arena" --center
```

### Strategy B: Player Spawn Alignment (`--spawn-idx`)
Source maps define player spawns using `info_player_start` and `info_player_deathmatch` entities. The converter can anchor the table at any spawn point and adopt its facing yaw:

```bash
# Align table to the first player spawn point (index 0):
py client/tools/convert_gmod_map.py "map.bsp" --spawn-idx 0

# Align table to an alternate spawn point:
py client/tools/convert_gmod_map.py "map.bsp" --spawn-idx 1
```

### Strategy C: Exact Hammer Coordinates (`--table-pos`)
If you know the exact Hammer coordinates $(X, Y, Z)$ where you want the table to stand (e.g. from Hammer Editor or the in-game `getpos` console command in GMod):

```bash
py client/tools/convert_gmod_map.py "map.bsp" --table-pos 520 -1150 64 --table-yaw 180
```

### Strategy D: Facing Direction (`--table-yaw`)
Sets the facing angle (in degrees) of the table relative to the map:
- `0` = Facing East (+X in Hammer)
- `90` = Facing North (+Y in Hammer)
- `180` = Facing West (-X in Hammer)
- `270` = Facing South (-Y in Hammer)

### Strategy E: Fine-Tuning Offset (`--table-offset`)
Adjusts the table in Godot meters relative to the selected anchor point:
`--table-offset OX OY OZ` (e.g. `--table-offset 0.0 -0.5 1.0` moves the table 0.5m down and 1m forward).

---

## 7. Multi-Map Archives

Many Steam Workshop items and `.zip` archives bundle several map versions (e.g., day, night, snow, or clean variants). 

To select a specific map from an archive containing multiple `.bsp` files, use the `--map` option:

```bash
# List and select a specific variant:
py client/tools/convert_gmod_map.py "map_bundle.zip" --map "custom_map_night" --name "Custom Map (Night)"
```

If `--map` is omitted and multiple maps are found, the converter automatically selects the main variant (prioritizing the one matching the addon name) and logs all available options.

---

## 8. Materials & Texture Pipeline

### Valve Texture Format (`.vtf`)
The tool contains a built-in vectorized decoder for `.vtf` textures. It automatically decodes:
- **Compressed formats:** DXT1 (BC1), DXT3 (BC2), DXT5 (BC3)
- **Uncompressed formats:** BGR888, BGRA8888, RGB888, RGBA8888, UV8888, I8 (Grayscale)
- **Mipmaps:** Automatically selects the base full-resolution mip level.

Decoded images are encoded as PNGs and embedded directly into the binary GLB buffer views.

### Valve Material Type (`.vmt`)
Material definitions (`LightmappedGeneric`, `VertexLitGeneric`, `UnlitGeneric`, `WorldVertexTransition`) are parsed to resolve texture references, translucency, and surface properties into standard glTF 2.0 PBR materials.

### External / Loose Materials (`--materials-dir`)
If a map relies on custom loose textures located in an external directory rather than inside the `.bsp` or `.gma`:

```bash
py client/tools/convert_gmod_map.py "map.bsp" --materials-dir "path/to/extracted/materials"
```

### Procedural Fallbacks
If specific Valve base game textures (such as default Half-Life 2 materials) are not present in the map package, the converter automatically falls back to reflectivity-matched PBR materials with subtle surface noise, preventing missing purple/black checkerboard artifacts.

---

## 9. Atmospheric Lighting & Environment

The converter inspects the map's entity table for environment lighting:
- **`light_environment`**: Extracted angles determine the directional sun's `pitch` and `yaw`. Color and intensity are scaled into Godot physical directional light values.
- **`worldspawn`**: The `skyname` property is matched against a database of sky presets (daylight, sunset, dusk, overcast, night) to configure procedural sky colors and horizon gradients in `background.json`.

You can freely customize the resulting `background.json` after conversion. See [README.md](README.md) for complete details on all `background.json` properties.

---

## 10. Command-Line Reference

| Argument | Description | Default |
| :--- | :--- | :--- |
| `input_path` | Path to `.bsp`, `.gma`, or `.zip` file | *(Required)* |
| `--name`, `-n` | In-game display name for the background | Map file name |
| `--map` | Specific map name to extract from multi-map archive | First / best match |
| `--out`, `-o` | Custom output directory | `~/.unciv-vr/Backgrounds/<Name>/` |
| `--center`, `--middle` | Auto-detect lowest floor basin and center table | `false` |
| `--spawn-idx` | Index of player spawn entity to align to | `0` |
| `--table-pos X Y Z` | Table location in Hammer units | Center or spawn |
| `--table-yaw DEG` | Table orientation in degrees ($0^\circ \text{--} 360^\circ$) | Spawn yaw or $180^\circ$ |
| `--table-offset OX OY OZ` | Fine-tuning offset in Godot meters | `0.0 0.0 0.0` |
| `--materials-dir`, `-m` | Path to loose `materials/` folder | None |
| `--scale`, `-s` | Scale factor from Hammer units to meters | `0.0254` |
| `--no-install` | Do not copy into `~/.unciv-vr/Backgrounds/` | `false` |

---

## 11. Testing Your Background

### In-Engine Test
Launch the game directly into your new background via the command line:

```bash
godot --path client -- --background=MyMap
```

`--background` takes the folder name, not the title: the converter names the folder after `--name` with the spaces
and punctuation taken out ("My Map" becomes `MyMap`), and prints where it put it.

### Settings Menu
Or start Unciv VR normally and pick it in **Settings > Look > Background** (the Settings button on the table, or O on the desktop). Backgrounds of yours say where they come from in the list ("from C:/Users/you/.unciv-vr/Backgrounds/MyMap").
