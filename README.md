# Unciv VR

A reimagined, VR-first frontend for [Unciv](https://github.com/yairm210/Unciv), using Godot with OpenXR.

```
Godot client (client/)  ⇄  TCP, JSON lines, 127.0.0.1:8765  ⇄  unciv-bridge (unciv/bridge/)
rendering, VR interaction                                       Unciv's real rules, AI and turns, headless
```

## One-time setup
- **JDK 21** (e.g. Eclipse Temurin 21, with "set JAVA_HOME" ticked)
- **Godot 4.7.x**, standard build (GDScript)
- **Quest 2 via Link:** Meta Quest Link app → Settings → General → set Meta Quest Link as the active OpenXR runtime
- Optional: **Python 3** to run the bridge's smoke test

## Every session
1. `cd unciv` then `gradlew.bat :bridge:run` (first time: several minutes of downloads)
2. Open `client\project.godot` in Godot and press F5

Details: [client/README.md](client/README.md), [bridge README](unciv/bridge/README.md),
[protocol](unciv/bridge/PROTOCOL.md).

## Roadmap
0. **Proof of concept**: bridge, tabletop map, select/move units, found cities, end turn (this)
1. Turn loop polish: combat, worker improvements, unit info on the wrist, bridge auto-launch
2. Cities (production, growth, the city diorama) and research (the tech constellation)
3. Borders, diplomacy, trade, religion
4. Art pass: models for units and buildings, terrain detail, sound
