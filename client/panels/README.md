# Panels

A **panel** is a board with a list on it, built from what the game already knows: your units, your cities, the
wonders overview, anything the bridge can tell the client. Each one is a folder with a `panel.json`; there's no
code to write. Turn panels on and off in **Settings > Panels**.

Unciv VR comes with five, made the same way you'd make yours:

- **Units** (`Units/`, on to start with): every unit you have, the ones waiting for orders first, with what each
  is doing, its moves and its health. Click one to select it.
- **Cities** (`Cities/`, on to start with, and shorter): every city you have, the capital first, with what each is
  building (its picture, and how many turns) and how big it is. Click one to open its card.
- **Military** (`Military/`, off to start with): every military unit you have, filtering out civilian units
  (`"filter": {"civilian": false}`). Click one to select it.
- **Rankings** (`Rankings/`, off to start with): current score rankings of all known civilizations, fetched
  from the politics overview and sorted by score.
- **Wonders** (`Wonders/`, off to start with): Unciv's wonders overview by era - an example of a panel that asks
  the bridge for its rows instead of reading them from the game state. Click a built one to look at it.

In VR a panel stands beside the table; hold the trigger on the strip along its top to move it, and point at it
and push the right stick to scroll. On the desktop panels sit down the left side of the window.

## Where panels live

| Folder | What's there |
| --- | --- |
| `client/panels/<Name>/` | The built-in panels |
| `~/.unciv-vr/Panels/<Name>/` (Windows: `C:\Users\<you>\.unciv-vr\Panels\<Name>\`) | Your own and downloaded ones, next to the saved games |

```
MyPanel/
  panel.json
```

A panel is read when the game starts, so restart the game after adding one. A built-in panel wins over one of
yours with the same folder name, so give yours a name of its own.

## panel.json

Unciv-style json; `//` comments are allowed. Only `source` is required.

```json
{
	"name": "Idle soldiers",
	"author": "you",
	"description": "Shown in Settings > Panels",
	"shown": true,
	"size": [0.3, 0.8],
	"home": [-1.02, 0.42, 0.3, 62],
	"icon": "other:Shield",
	"title": "Idle soldiers ({count})",
	"source": "units",
	"filter": {"civilian": false, "idle": true},
	"sort": ["-health", "name"],
	"row": {
		"icon": {"kind": "unit", "name": "{name}", "civ": "{civ}"},
		"text": "{instanceName|name}",
		"detail": "{unitType}{canPromote?'  -  promotion ready'}",
		"right": "{movement}/{maxMovement}",
		"bar": {"value": "{health}", "max": 100}
	},
	"selected": "unit",
	"click": {"do": "select_unit", "id": "{id}"},
	"empty": "Everyone has orders."
}
```

| Key | Meaning |
| --- | --- |
| `name`, `author`, `description` | Shown in Settings > Panels. `name` is also the title, unless `title` says otherwise |
| `shown` | Whether it's up until the player says otherwise in Settings (default `true`) |
| `size` | `[width, height]` in metres in VR (default `[0.3, 0.8]`, tall and thin). The board is `width` pixels across (default 360) and as tall as that shape makes it |
| `home` | Where it stands in VR before anyone moves it: `[x, y, z, yaw]` from the middle of the table top, in metres and degrees. You sit on the +Z side; yaw turns it to face you (60 or so on your left, -60 on your right) |
| `tilt` | Leans it back (degrees, default 0) |
| `icon` | An icon beside the title (see Icons) |
| `title` | The title, a template; `{count}` is how many rows there are |
| `source` | Where the rows come from (see Sources) |
| `filter` | `{"field": value, ...}`: only rows where every field matches (true / false, a number or a text) |
| `sort` | A field, or a list of them: ascending, or descending with a `-` in front (`"-health"`). Rows without the field go last |
| `group` | A field to group rows by, with a heading for each; `groupTitle` (a template) words the heading (default `{<group>}`) |
| `row` | How a row looks: `icon`, `text` (default `{name}`), `detail` (a dimmer line under it), `right` (a short text on the right) and `bar` (see below). All but `icon` and `bar` are templates |
| `selected` | `"unit"` or `"city"`: the row of the selected unit (matched on `id`) or city (matched on `name`) stands out |
| `click` | What clicking a row does (see Clicks). Without it the rows are just to read |
| `empty` | Shown when there are no rows |

**bar**: `{"value": "{health}", "max": 100, "hideWhenFull": true}` draws a thin bar under the text, green when
nearly full, then yellow, then red; it's left out when full unless `hideWhenFull` is false. `max` can be a template
too (`"{xpForNextPromotion}"`).

## Sources

The rows are a list of objects (one per row) from the bridge, in one of two ways. The bridge's protocol is in
`unciv/bridge/PROTOCOL.md`; every field it lists can be used in a template.

- **A list in the game state** - `"source": "units"`. That's a list in `getState`, which the client asks for after
  everything you do, so the panel is always up to date and costs nothing extra. Useful ones: `units` (yours:
  `id, name, instanceName, civ, unitType, x, y, health, movement, maxMovement, idle, due, action, civilian,
  fortified, sleeping, moving, automated, embarked, canPromote, strength, rangedStrength, range`), `cities`
  (`name, x, y, population, isCapital, health, maxHealth, producing, producingTurns, turnsToGrowth, isPuppet,
  isBeingRazed, canBombard`), `civs`, `alerts`, `blockers`. A dotted path reaches deeper (`"game.mods"`).
- **A request** - `"source": {"request": "getOverview", "params": {"tab": "wonders"}, "path": "wonders"}`. The
  client asks the bridge with those params and takes the list at `path` in the answer. Only methods that read
  are allowed: `getState`, `getOverview`, `getDiplomacy`, `getTechs`, `getPolicies`, `getVictory`, `getEspionage`,
  `getReligionChoices`, `getGreatPersonChoices`, `getVoteChoices`, `getRuleset`, `getCity`, `getUnit`, `getTile`,
  `getTradeOptions`, `listSaves`. It's asked again each turn and when the panel is turned on; add
  `"refresh": "always"` to the source to ask after everything you do (for things that change mid-turn - but
  mind that some requests take a moment). `getOverview` has a tab for most things Unciv's Empire Overview shows
  (`cities, stats, trades, units, politics, resources, religion, wonders, notifications, espionage`).

## Templates

Text in `{ }` is filled in from the row:

| Template | Gives |
| --- | --- |
| `{name}` | the row's `name` |
| `{location.x}`, `{promotions.0}` | deeper: a field of a field, or an item of a list by number |
| `{promotions.size}` | how many things a list holds (or how long a text is) |
| `{instanceName\|name}` | the first one that isn't empty |
| `{action\|'Waiting for orders'}` | text in single quotes is used as it is |
| `{canPromote?'promotion ready'}` | the text only when the field is set: true, a number above 0, text or a list that isn't empty (Unciv uses -1 for "doesn't apply") |
| `{producingTurns#'turn'}` | a count with its word: "1 turn", "38 turns"; nothing unless it's above 0 |

Whole numbers show without decimals (`2.0` shows as `2`), other numbers with one; a list shows as its items
with commas; `true` shows as "yes".

## Icons

`"kind:name"` or `{"kind": ..., "name": ..., "civ": ...}`, where `name` and `civ` are templates. Kinds are the
folders of Unciv's own images the client already uses: `unit`, `building`, `improvement`, `resource`, `tech`,
`policy`, `promotion`, `nation`, `stat`, `other`, `tile`, `unittype`, `religion` - and `construction`, for
whatever a city builds (a unit, a building, or Gold / Science / Culture / Faith). A `unit` with a `civ` is a badge
in that civ's colours, like the unit card's; buildings, improvements and resources sit on a light disc. A name
Unciv has no picture for just shows no icon - check the name against `unciv/android/Images.*`.

## Clicks

`"click": {"do": ..., ...}`, with the fields filled in from the clicked row. A panel can only do these:

| `do` | Needs | Does |
| --- | --- | --- |
| `select_unit` | `id` | selects that unit of yours (the view slides to it) |
| `look_at` | `x`, `y` | slides the map to that tile |
| `open_city` | `name` | opens one of your cities' card |
| `city_view` | `name` | goes into one of your cities |

## Checking yours

When a `panel.json` can't be used, the game leaves it out and says why in its log (Godot's `user://logs/godot.log`;
on Windows `%APPDATA%\Godot\app_userdata\Unciv VR\logs\godot.log`) and in the console. `--scenario=panels` (see the client README) shows every panel and takes pictures of them.

## Licence

The built-in panels are part of Unciv VR, under the Mozilla Public License 2.0, like the rest of the project.
