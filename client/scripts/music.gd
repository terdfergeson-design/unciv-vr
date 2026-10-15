# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node
## Unciv's music, chosen the way Unciv's MusicController chooses it (unciv/core/.../ui/audio/MusicController.kt).
##
## Unciv ships no music. Its Options > Sound has a "Download music" button that fetches one track, "Thatched
## Villagers", and players and mods add their own; so does this client. Music is read when the game runs from
## ~/.unciv-vr/Music (and client/music), where Settings > Sound's Download button (the bridge's downloadMusic)
## puts Unciv's track. Each sub-folder there counts as a mod's music folder - a music pack.
##
## Tracks are picked by file name, like Unciv's: "<Context> - <Mood>.mp3", where the context is usually a nation,
## civ, tech or wonder name ("Babylon - War", "Writing - Researched", "Thatched Villagers - Ambient") and the mood one
## of the MOOD constants. [method choose] looks for a prefix (context) and a suffix (mood), the flags saying which must
## match. When a track ends there is a pause (Settings > Sound), then another Ambient track. Flat, not placed on the
## table: it's the room's music.

const ModFolders := preload("res://scripts/mod_folders.gd")
const KIND := "Music"
const EXTENSIONS := ["mp3", "ogg", "wav"]
## What Unciv's (and our) Download music button saves, without its extension
const DEFAULT_TRACK := "Thatched Villagers - Ambient"
## Unciv's MusicController.maxVolume: the volume setting is scaled by this
const MAX_VOLUME := 0.6
const FADE := 0.9              # seconds, Unciv's defaultFadeDuration; SLOW_FADE makes it 5 times longer
const HISTORY := 8             # recent tracks, played again only when nothing else fits

# Unciv's MusicMood
const THEME := "Theme"
const PEACE := "Peace"
const WAR := "War"
const DEFEAT := "Defeat"
const MENU := "Menu"
const AMBIENT := "Ambient"
const GOLDEN := "Golden"
const WONDER := "Wonder"
const RESEARCHED := "Researched"
const VICTORY := "Victory"
const THEME_OR_PEACE := [THEME, PEACE]

# Unciv's MusicTrackChooserFlags, as bits
const PREFIX_MUST_MATCH := 1
const SUFFIX_MUST_MATCH := 2
const SLOW_FADE := 4
const PLAY_SINGLE := 8         # stop after this track instead of going on to the next
const PLAY_DEFAULT_FILE := 16  # Thatched Villagers, if it's there
# ... and its ready-made sets
const FLAGS_DEFAULT := SUFFIX_MUST_MATCH
const FLAGS_PLAY_DEFAULT := PLAY_DEFAULT_FILE | PLAY_SINGLE
const FLAGS_SELECT_NATION := PREFIX_MUST_MATCH
const FLAGS_SPECIFIC := PREFIX_MUST_MATCH | SUFFIX_MUST_MATCH
const FLAGS_NEXT_TURN := PREFIX_MUST_MATCH | SLOW_FADE
const FLAGS_NONE := 0

## Emitted when the track changes or stops: {"track", "pack", "path", "state"} (see [method now_playing]).
signal changed(info: Dictionary)

var volume := 0.5              # 0 - 1, Settings > Sound
var pause_between := 10.0      # seconds of silence between tracks

var _players: Array[AudioStreamPlayer] = []
var _current: AudioStreamPlayer = null
var _current_path := ""
var _history: Array[String] = []
var _state := "idle"           # idle / playing / single (stops after this one) / silence / paused
var _silence := 0.0
var _tweens := {}              # player -> its fade Tween
var _last_choice := ""         # for tests: "prefix|suffix|flags -> path"


func _ready() -> void:
	for i in 2:   # two, so one track can fade over into the next
		var player := AudioStreamPlayer.new()
		player.volume_db = -80.0
		player.finished.connect(_on_finished.bind(player))
		add_child(player)
		_players.append(player)


func _process(delta: float) -> void:
	if _state != "silence":
		return
	_silence -= delta
	if _silence <= 0.0:
		_silence = maxf(pause_between, 1.0)   # tried again after another pause if nothing can be found
		choose()


# region finding tracks ------------------------------------------------------------------------

## Where music is looked for: client/music, then ~/.unciv-vr/Music. Each sub-folder is a pack (a mod's music).
static func search_dirs() -> Array:
	return ModFolders.search_dirs(KIND)


## Every track that can be played: absolute paths.
static func all_tracks() -> Array[String]:
	var out: Array[String] = []
	for dir_path: String in search_dirs():
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():   # packs, like Unciv's mods/<mod>/music
			_add_files(out, dir_path.path_join(sub))
		_add_files(out, dir_path)
	return out


static func _add_files(out: Array[String], dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension().to_lower() in EXTENSIONS:
			out.append(dir_path.path_join(file))


## Unciv's default track, if it has been downloaded (or put there by hand): its path, or "".
static func default_track() -> String:
	for dir_path: String in search_dirs():
		for ext: String in EXTENSIONS:
			var path: String = dir_path.path_join(DEFAULT_TRACK + "." + ext)
			if FileAccess.file_exists(path):
				return path
	return ""


## The folder Download music saves to (~/.unciv-vr/Music), as the player would type it.
static func user_dir() -> String:
	var dirs := search_dirs()
	return str(dirs[dirs.size() - 1])


## {"track": "Thatched Villagers - Ambient", "pack": "" or the sub-folder} for a path.
static func describe(path: String) -> Dictionary:
	if path == "":
		return {"track": "", "pack": ""}
	var pack := path.get_base_dir().get_file()
	for dir_path: String in search_dirs():
		if path.get_base_dir().simplify_path() == str(dir_path).simplify_path():
			pack = ""
	return {"track": path.get_file().get_basename(), "pack": pack}


# region choosing ------------------------------------------------------------------------------

## Unciv's chooseTrack: picks a track whose name starts with [param prefix] (the context - a civ, nation, tech,
## wonder...) and ends with one of [param suffixes] (a mood, or a list of them tried in turn), as [param flags]
## say, and fades over to it. Returns whether something was found (and is now playing or already was).
## Called with nothing: a new Ambient track.
func choose(prefix := "", suffixes: Variant = AMBIENT, flags := FLAGS_DEFAULT) -> bool:
	if suffixes is Array:
		for suffix: String in suffixes:
			if _choose_one(prefix, suffix, flags):
				return true
		return false
	return _choose_one(prefix, str(suffixes), flags)


func _choose_one(prefix: String, suffix: String, flags: int) -> bool:
	if volume <= 0.0:
		return false
	var path := choose_file(prefix, suffix, flags, _history)
	_last_choice = "%s|%s|%d -> %s" % [prefix, suffix, flags, path]
	if path == "":
		return false
	return _start(path, flags)


## Unciv's chooseFile: the best match among [method all_tracks] - a matching prefix first, then a matching suffix,
## then one not played lately; random among equals. "" when the must-match flags leave nothing.
static func choose_file(prefix: String, suffix: String, flags: int, history: Array = []) -> String:
	if flags & PLAY_DEFAULT_FILE:
		var fallback := default_track()
		if fallback != "":
			return fallback
	return pick(all_tracks(), prefix, suffix, flags, history)


## The choosing part of [method choose_file], from [param tracks] (paths), so tests can try it on made-up names.
static func pick(tracks: Array, prefix: String, suffix: String, flags: int, history: Array = []) -> String:
	var best: Array[String] = []
	var best_score := 99
	for path: String in tracks:
		var track := path.get_file().get_basename()
		var prefix_ok := track.begins_with(prefix)
		var suffix_ok := track.ends_with(suffix)
		if (flags & PREFIX_MUST_MATCH and not prefix_ok) or (flags & SUFFIX_MUST_MATCH and not suffix_ok):
			continue
		var score := (0 if prefix_ok else 4) + (0 if suffix_ok else 2) + (1 if path in history else 0)
		if score < best_score:
			best_score = score
			best.clear()
		if score == best_score:
			best.append(path)
	return best.pick_random() if not best.is_empty() else ""


func _start(path: String, flags: int) -> bool:
	if path == _current_path and _current != null and _current.playing:
		if _state == "paused":
			resume()
		return true
	var sound := load_track(path)
	if sound == null:
		return false
	_history.erase(path)
	_history.append(path)
	while _history.size() > HISTORY:
		_history.pop_front()
	var fade := FADE * (5.0 if flags & SLOW_FADE else 1.0)
	var old := _current
	var player := _players[1] if _current == _players[0] else _players[0]
	_fade(player, -80.0, 0.0)
	player.stop()
	player.stream = sound
	player.volume_db = -80.0
	player.play()
	_fade(player, _target_db(), fade)
	if old != null and old.playing:
		_fade(old, -80.0, fade, true)
	_current = player
	_current_path = path
	_state = "single" if flags & PLAY_SINGLE else "playing"
	_emit()
	return true


## Reads a track (mp3, ogg or wav) when the game runs; null if it can't.
static func load_track(path: String) -> AudioStream:
	var sound: AudioStream = null
	match path.get_extension().to_lower():
		"mp3": sound = AudioStreamMP3.load_from_file(path)
		"ogg": sound = AudioStreamOggVorbis.load_from_file(path)
		"wav": sound = AudioStreamWAV.load_from_file(path)
	if sound == null:
		push_warning("Couldn't read the music track %s" % path)
	return sound


func _on_finished(player: AudioStreamPlayer) -> void:
	if player != _current or _state == "paused":
		return
	_current = null
	_current_path = ""
	if _state == "single":
		_state = "idle"
	else:
		_state = "silence"
		_silence = pause_between
	_emit()


# region controls ------------------------------------------------------------------------------

## Settings > Sound: 0 - 1. Off stops the music; turning it up when nothing plays starts Unciv's own track
## (or, without it, whatever there is), like Unciv's slider.
func set_volume(level: float) -> void:
	var was := volume
	volume = clampf(level, 0.0, 1.0)
	if volume <= 0.0:
		stop()
		return
	if _current != null and _current.playing:
		_fade(_current, _target_db(), 0.2)
	elif was <= 0.0 or _state == "idle":
		if not choose("", AMBIENT, PLAY_DEFAULT_FILE):   # Unciv plays it once (PlaySingle); here the music goes on
			choose("", AMBIENT, FLAGS_NONE)


## Fades the music out and goes quiet until something chooses a track again.
func stop() -> void:
	for player in _players:
		if player.playing:
			_fade(player, -80.0, FADE, true)
	_current = null
	_current_path = ""
	_state = "idle"
	_emit()


func pause() -> void:
	if _current == null or _state == "paused":
		return
	_state = "paused"
	_current.stream_paused = true
	_emit()


func resume() -> void:
	if _state != "paused" or _current == null:
		return
	_current.stream_paused = false
	_current.volume_db = _target_db()
	_state = "playing"
	_emit()


## Unciv's "next track" button: any other track.
func next_track() -> bool:
	if _state == "paused" and _current != null:
		_current.stream_paused = false
	return choose("", AMBIENT, FLAGS_NONE)


func is_playing() -> bool:
	return _current != null and _current.playing and _state != "paused"


## What's on: {"track", "pack", "path", "state"} - state is idle / playing / single / silence / paused.
func now_playing() -> Dictionary:
	var info := describe(_current_path)
	info["path"] = _current_path
	info["state"] = _state
	return info


func last_choice() -> String:
	return _last_choice


func _target_db() -> float:
	return linear_to_db(clampf(volume * MAX_VOLUME, 0.0001, 1.0))


func _fade(player: AudioStreamPlayer, to_db: float, seconds: float, then_stop := false) -> void:
	var running: Tween = _tweens.get(player)
	if running != null and running.is_valid():
		running.kill()
	if seconds <= 0.0:
		player.volume_db = to_db
		if then_stop:
			player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, seconds)
	if then_stop:
		tween.tween_callback(player.stop)
	_tweens[player] = tween


func _emit() -> void:
	changed.emit(now_playing())
