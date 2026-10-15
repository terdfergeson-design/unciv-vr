# Unciv VR

A VR-first way to play [Unciv](https://github.com/yairm210/Unciv), the open-source Civilization V remake: the
map is a tabletop in front of you, your units and cities stand on it, and Unciv's own rules, AI and turns run
underneath. Built with Godot 4.7 and OpenXR.

It plays in three ways:
- **PC VR** - SteamVR or Meta Quest Link (Air Link works too).
- **On the desktop** - the same game in a window, with mouse and keyboard, no headset needed.
- **Standalone on a Quest 2 / 3 / Pro** - the whole game, Unciv's engine included, runs inside one Android app.

```
Godot client (client/)  <->  TCP, JSON lines, 127.0.0.1:8765  <->  unciv-bridge (unciv/bridge/)
the table, VR and desktop UI                                       Unciv's real rules, AI and turns, headless
```
On the PC the bridge is a separate Java process that the client starts by itself; in the Quest app it runs inside
the app (`unciv/bridge-android`). Either way the client talks to it the same way.

## Screenshots
<img width="200" src="https://github.com/user-attachments/assets/f0c01178-aaca-4f82-b709-6755ecd59a29" /><img width="200" src="https://github.com/user-attachments/assets/86976333-5c5f-4f12-a498-b5600db9204a" /><img width="200" src="https://github.com/user-attachments/assets/5baba668-1703-4b25-bd30-75cd505ebc2f" /><img width="200" src="https://github.com/user-attachments/assets/49bc03ff-be78-48f1-804d-6ffa547efc11" /><img width="200" src="https://github.com/user-attachments/assets/a6664441-0ec3-4fda-bdb0-f61b52aefa47" />





Original icons from Unciv have been tinted and scaled.  Shared under various CC licenses.
[View Credits](https://github.com/terdfergeson-design/Unciv/blob/vr-bridge/docs/Credits.md)

## What you can do
- **Play a whole game of Unciv**: Vanilla or Gods & Kings rules, any civ, map size, difficulty and victory type;
  new game, quick start, continue, save and load.
- **Units**: select, move and attack on the table (paths, turns and expected damage shown as you aim), every Unciv
  unit action, promotions, upgrades; other players' moves and battles play back on the table after your turn.
- **Cities**: a city view that does everything Unciv's city screen does - worked tiles, buying tiles, the production
  queue, buying and selling, specialists, focus, religion. Unciv's suggested city spots for settlers.
- **Empire**: the tech tree, policies, diplomacy and trade, religion, espionage, victory progress, and all nine tabs of
  Unciv's empire overview - on boards around the table you can move wherever you like.
- **After a game ends**, replay the changing borders and city locations with the whole map zoomed out on the table.
- **Unciv's Civilopedia and tutorials**, Unciv's popups and decisions, Unciv's icons and sound effects (in VR, sounds
  come from where they happen on the table).
- **Unciv's languages**: the game in any of about 50 languages Unciv has been translated into (see Languages below).
- **Make it yours**: backgrounds and tables to stand in (or move the table anywhere in a big 3D background), 3D or
  Unciv-style 2D tilesets and unit sets, and panels - all of which you can add your own of, no code needed.
- **VR controls** with the right controller alone: point and pull the trigger. You see the controllers you're
  actually holding (Quest Touch, Index, Vive...), with optional labels saying what each button does right now.

## Getting it running on the PC
One-time setup:
- **JDK 21** (for example Eclipse Temurin 21, with "Set JAVA_HOME" ticked).
- **Godot 4.7.x**, the standard build.
- **For VR on a Quest:** in the Meta Quest Link app, Settings > General, make Meta Quest Link the active OpenXR
  runtime. For SteamVR headsets, SteamVR as the OpenXR runtime.
- Clone with the Unciv fork included: `git clone --recurse-submodules <this repository>`.

Then open `client\project.godot` in Godot and press **F5**. The client starts the bridge itself (the first time
takes several minutes of downloads) and stops it when you quit. With no headset running it opens in a window.

## Building a portable Windows release
With Godot 4.7.2 Windows export templates and JDK 21 installed, run this from the repository folder:

    powershell -ExecutionPolicy Bypass -File client\tools\build_windows.ps1

It creates `build\UncivVR-v<version>-windows.zip` (the version comes from the export preset), containing the Windows client, Unciv bridge and assets,
and a trimmed Java runtime. The player does not need Godot or Java installed. The first build may download Gradle
and its dependencies.

## Building the Quest app
Install Android Studio (with its Command-line Tools) and Godot 4.7.2's export templates, set the Android SDK and a
JDK 17 in Godot's Editor Settings > Export > Android, then from the repository folder:

    client\tools\build_quest.bat

That makes `build\UncivVR-Quest.apk`, signed with Godot's debug key. Install it with SideQuest, or with
`client\tools\build_quest.bat install` over a USB data cable (the Quest needs developer mode on). It shows up in the
headset's Library under Unknown sources.

For a build to share, sign it with your own key: `client\tools\build_quest.bat release` makes
`build\UncivVR-v0.2.0-beta-quest.apk` (the version comes from the export preset) and prints the certificate it was
signed with. More in [client/README.md](client/README.md#the-standalone-quest-app).

## Where things are
| | |
|---|---|
| `client/` | The Godot project: everything you see and click. Its [README](client/README.md) has the controls, settings and features in full. |
| `client/backgrounds`, `tables`, `tilesets`, `panels` | Built-in surroundings, tilesets and panels; each folder's README says how to make your own (they go in `~/.unciv-vr`). |
| `client/tools/` | Build and content scripts: the Quest build, data packing, tileset and background generators, a GMod map converter. |
| `unciv/` | Our fork of Unciv (a git submodule, branch `vr-bridge`). |
| `unciv/bridge/` | The bridge: Unciv's game run headless behind a small JSON protocol - [README](unciv/bridge/README.md), [protocol](unciv/bridge/PROTOCOL.md). |
| `unciv/bridge-android/` | The bridge as a Godot Android plugin, for the Quest app. |

Your saves, settings and own content live in `~/.unciv-vr` (Windows: `C:\Users\<you>\.unciv-vr`) on the PC, and in
the app's own storage on the Quest.

## Languages
**Now:** Settings > Gameplay > Language offers every language Unciv has a translation for (about 50, with how
complete each is), using Unciv's own translation files by Unciv's translators. The game's side is translated: messages
and popups, notifications, descriptions, the Civilopedia and tutorials, quests, victory texts, and the names of units,
buildings, techs, nations and cities - plus those of our buttons that use Unciv's own words.
German, Arabic, Hebrew, Spanish, French, Italian, Brazilian Portuguese, Swedish, European Portuguese, Dutch,
Polish, Turkish, Indonesian, Japanese, Russian, Ukrainian, Czech, Hungarian, Romanian, Croatian, Catalan,
Galician, Norwegian, Esperanto, Simplified Chinese, Traditional Chinese, Vietnamese, Toki Pona, Maltese,
Korean and Filipino have draft translations covering the frontend menus, city and
empire boards, diplomacy, religion, map replay, controller hints, built-in lists and tutorial instructions.
Select **Arabic / العربية** or **Hebrew / עברית** for a right-to-left interface. Both now include draft Unciv
game-content catalogs: built-in object names, promotions and shared effect descriptions. Unfinished entries still
fall back to English. See [content translation coverage](client/translations/CONTENT.md). Bundled Noto fonts cover
Latin, Cyrillic, Arabic, Hebrew, Japanese, Chinese and Korean on Windows and Quest. Other scripts may use system font fallbacks.
The VR keyboard includes accents for each supported Latin-script language, Arabic/Hebrew and Russian/Ukrainian layouts, and Japanese
hiragana/katakana input with a Latin switch (no kanji conversion). These passes are ready
for wording and headset layout review.
Korean adds Hangul composition, Vietnamese adds vowel and tone keys, Maltese adds ċġħż, and Filipino adds ñ.
Chinese name entry currently uses Latin keys; Pinyin/Zhuyin character conversion is not implemented.
The latest catalogs reuse Unciv terms and contain translation drafts with terminology edits;
they have not yet had native-speaker or in-game visual review. Details and content coverage are in
[the translation guide](client/translations/README.md).

**Next**, to go all the way:
- **More frontend languages**: review the existing catalogs, then add languages in `client/translations/`. Other languages still
  use Unciv's translations where available and English for the remaining frontend wording.
- **Layout**: longer languages (German, Russian...) overflow some buttons and cards; Godot's pseudo-localization
  finds those spots and any text still untranslated.
- **Fonts and scripts**: extend bundled font coverage to more scripts and review RTL layouts on the headset.
- **Typing**: further keyboard layouts for naming cities, units and saves.

## Not there yet
Unciv mods, world wrap and music; multiplayer is left out on purpose. On the Quest,
text is a little softer than over Link, since the headset renders at a lower resolution on its own.

## Licence and credits
Unciv VR is under the Mozilla Public License 2.0, like Unciv ([LICENSE](LICENSE)). Unciv's icons and sound effects
are used under their authors' licences (CC BY / CC BY-SA / CC0); on the PC they're read from the Unciv checkout, and
the Quest app carries them with Unciv's credits list. See [CREDITS.md](CREDITS.md) for all of it.
