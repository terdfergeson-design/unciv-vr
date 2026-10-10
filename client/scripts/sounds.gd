# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Unciv's sound effects. Like its icons, they're read when the game runs from the Unciv checkout next to
## us (../unciv/android/assets/sounds) and never copied into this repo; players and mods can put their own
## in ~/.unciv-vr/Sounds (or client/sounds) under the same names to replace them.
##
## Sounds are named the way Unciv names them - "click", "whoosh", "coin", each unit's attackSound - so the
## client plays what Unciv itself would play, and the bridge can simply pass a sound's name along.
##
## In VR a sound that happens somewhere on the table comes from there (play_at), while button clicks and
## the like are flat (play). The city view's ambience loops from the table, fading in and out.

const ModFolders := preload("res://scripts/mod_folders.gd")
const KIND := "Sounds"
const EXTENSIONS := ["mp3", "ogg", "wav"]
const VOICES := 8                  # sounds that can overlap before the oldest is cut off
const AMBIENCE_FADE := 1.5         # seconds
## Unciv's own names, for the ones the client plays itself (the rest come from the bridge or the ruleset).
const CLICK := "click"
const WHOOSH := "whoosh"
const COIN := "coin"
const PAPER := "paper"
const POLICY := "policy"
const CHOIR := "choir"
const CHIMES := "chimes"
const CONSTRUCTION := "construction"
const PROMOTE := "promote"
const BOMBARD := "bombard"
const SWAP := "swap"
const SLIDER := "slider"
const NOTIFICATION := "notification1"     # a message from the game waits for an answer
const TURN := "notification2"             # your turn comes round again

var effects_volume := 0.7   # 0 - 1, from Settings
var ambience_volume := 0.5

var _streams: Dictionary = {}      # name -> AudioStream, or null when there's no such sound
var _flat: Array[AudioStreamPlayer] = []
var _placed: Array[AudioStreamPlayer3D] = []
var _next_flat := 0
var _next_placed := 0
var _ambience: AudioStreamPlayer3D
var _ambience_name := ""
var _fade: Tween


func _ready() -> void:
	for i in VOICES:
		var flat := AudioStreamPlayer.new()
		add_child(flat)
		_flat.append(flat)
		var placed := AudioStreamPlayer3D.new()
		placed.unit_size = 4.0        # the table is about a metre across: carry across the room
		placed.max_db = 0.0
		add_child(placed)
		_placed.append(placed)
	_ambience = AudioStreamPlayer3D.new()
	_ambience.unit_size = 6.0
	add_child(_ambience)


## Where sounds are looked for, in order: a player's or mod's own first, then Unciv's own.
static func search_dirs() -> Array:
	var dirs: Array = ModFolders.search_dirs(KIND)
	dirs.append(ProjectSettings.globalize_path("res://").path_join("../unciv/android/assets/sounds").simplify_path())
	return dirs


## The file for [param name] ("click", "nonmetalhit"), with or without its extension, or "".
static func find(name: String) -> String:
	if name == "":
		return ""
	for dir_path: String in search_dirs():
		if name.get_extension().to_lower() in EXTENSIONS:
			var direct := dir_path.path_join(name)
			if FileAccess.file_exists(direct):
				return direct
			continue
		for ext: String in EXTENSIONS:
			var path := dir_path.path_join(name + "." + ext)
			if FileAccess.file_exists(path):
				return path
	return ""


## The sound called [param name], read the first time it's asked for; null when there isn't one.
func stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := find(name)
	var loaded: AudioStream = null
	if path != "":
		match path.get_extension().to_lower():
			"mp3": loaded = AudioStreamMP3.load_from_file(path)
			"ogg": loaded = AudioStreamOggVorbis.load_from_file(path)
			"wav": loaded = AudioStreamWAV.load_from_file(path)
	elif name != "":
		push_warning("No sound called %s (looked in %s)" % [name, ", ".join(search_dirs())])
	_streams[name] = loaded
	return loaded


## Plays [param name] flat, for buttons and anything that isn't somewhere in particular.
## [param volume] scales it (0 - 1). Unknown or empty names do nothing, like Unciv's "Silent".
func play(name: String, volume := 1.0) -> void:
	var sound := stream(name)
	if sound == null or effects_volume <= 0.0 or _flat.is_empty():
		return
	var player := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	player.stream = sound
	player.volume_db = linear_to_db(clampf(effects_volume * volume, 0.001, 1.0))
	player.play()


## Plays [param name] at [param where] (global), so in VR it comes from that spot on the table.
func play_at(name: String, where: Vector3, volume := 1.0) -> void:
	var sound := stream(name)
	if sound == null or effects_volume <= 0.0 or _placed.is_empty():
		return
	var player := _placed[_next_placed]
	_next_placed = (_next_placed + 1) % _placed.size()
	player.stream = sound
	player.global_position = where
	player.volume_db = linear_to_db(clampf(effects_volume * volume, 0.001, 1.0))
	player.play()


## Loops [param name] from [param where] (the city view's ambience), fading between tracks.
## An empty name fades the ambience out.
func ambience(name: String, where := Vector3.ZERO) -> void:
	if _ambience == null:
		return
	if name == _ambience_name:
		if _ambience.playing:
			_ambience.global_position = where
		return
	_ambience_name = name
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if name == "" or ambience_volume <= 0.0:
		if not _ambience.playing:
			return
		_fade = create_tween()
		_fade.tween_property(_ambience, "volume_db", -40.0, AMBIENCE_FADE)
		_fade.tween_callback(_ambience.stop)
		return
	var sound := stream(name)
	if sound == null:
		_ambience.stop()
		return
	if sound is AudioStreamOggVorbis:
		(sound as AudioStreamOggVorbis).loop = true
	elif sound is AudioStreamMP3:
		(sound as AudioStreamMP3).loop = true
	_ambience.stream = sound
	_ambience.global_position = where
	_ambience.volume_db = -40.0
	_ambience.play()
	_fade = create_tween()
	_fade.tween_property(_ambience, "volume_db", linear_to_db(clampf(ambience_volume, 0.001, 1.0)), AMBIENCE_FADE)


## The ambience follows the table when it's moved or the volume changes.
func set_volumes(effects: float, ambience_level: float) -> void:
	effects_volume = clampf(effects, 0.0, 1.0)
	ambience_volume = clampf(ambience_level, 0.0, 1.0)
	if _ambience == null:
		return      # volumes set before this node is in the tree (the client reads them from its settings)
	if _ambience.playing:
		if ambience_volume <= 0.0:
			var playing := _ambience_name
			_ambience_name = ""
			ambience(playing)   # fades it out and remembers nothing
			_ambience_name = playing
		else:
			_ambience.volume_db = linear_to_db(maxf(ambience_volume, 0.001))
	elif ambience_volume > 0.0 and _ambience_name != "":
		var again := _ambience_name
		_ambience_name = ""
		ambience(again, _ambience.global_position)


## Names of every sound that can be found, for tests and for the sounds page in Settings.
static func available() -> Array:
	var names: Array = []
	for dir_path: String in search_dirs():
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if file.get_extension().to_lower() in EXTENSIONS and file.get_basename() not in names:
				names.append(file.get_basename())
	names.sort()
	return names
