# Test saves

`everything.json` is an Unciv save with everything the test scenarios and screenshots need, so test runs start
from it instead of a new game plus debug commands and End turns (which is slow, and leaves what happens to chance):

- the Aztecs (so the Jaguar shows a civ's unique unit falling back to the Warrior model), turn 4 of a Small map
  with 3 AI players and 4 city-states, the whole map revealed, every civ and city-state met
- three cities, with a Warrior and a Worker stacked in the capital
- Archer, Swordsman, Spearman, Horseman, Catapult, Chariot Archer, Scout, Work Boats, Trireme, Settler,
  Great General, Great Prophets, and a free great person waiting to be picked
- at war with a neighbour whose war party (Swordsman, Horseman, Archer, Catapult, Spearman) stands next to our
  second city, so End turn always has fights to play back
- 1500 gold, 400 faith, 300 culture, a dozen ancient techs, four turns of history for the victory charts

Use it with `--load=res://tests/saves/everything.json` (the client sends `remember: false`, so it never replaces
your autosave), e.g. `--load=res://tests/saves/everything.json --no-launch --port=8799 --scenario=playback`.

To make it again (after a big Unciv update, or to add something), with a bridge started by hand with `--debug`:

```
godot --path client -- --new-game --map-size=Small --ai=3 --port=8799 --no-launch --scenario=make_test_save --then=save_test_game --screenshot=done.png
```

`scripts/dev_scenarios.gd` (`make_test_save`) lists exactly what goes in.
