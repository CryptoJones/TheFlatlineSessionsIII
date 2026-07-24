extends Node
## Crossfading background-music director (autoload).
##
## Same two-player crossfade design as the original engine. The sequels ship
## soundtrack-light: tracks land in assets/audio/music/<name>.ogg as they're
## produced, and a missing file is a graceful no-op so the scaffold runs silent.
## Also drives a playlist mode for the hidden anti-tamper room 1337.

const MUSIC_DIR := "res://assets/audio/music/"
const FADE := 1.2          # crossfade seconds
const MUSIC_DB := -8.0     # nominal playback level
const CHAPTER_TRACKS := {
	"ch01": "ch01_the_smoke",
	"ch02": "ch02_dog_solitude",
	"ch03": "ch03_florida",
	"ch04": "ch04_malibu",
	"ch05": "ch05_oracle_lost_tech",
	"ch06": "ch06_the_work",
	"ch07": "ch07_the_aleph",
	"ch08": "ch08_the_loas_price",
	"ch09": "ch09_underground",
	"ch10": "ch10_the_switch",
	"ch11": "ch11_siege_dog_solitude",
	"ch12": "ch12_mona_lisa_underdrive",
}

signal track_changed(track)

const SETTINGS_PATH := "user://settings.cfg"

var enabled := true
# User music level, linear 0.0–1.0 (1.0 == the nominal MUSIC_DB). Persisted.
var music_volume := 1.0
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _current := ""
var _cache := {}
var _playlist: Array = []
var _pl_idx := 0
var _pl_active := false
# What the game last asked for, tracked even while muted, so re-enabling
# music resumes the right cue instead of silence.
var _wanted := ""
var _wanted_list: Array = []

func _ready() -> void:
	_load_settings()
	_a = _make_player()
	_b = _make_player()
	_active = _a
	_a.finished.connect(_on_finished.bind(_a))
	_b.finished.connect(_on_finished.bind(_b))

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = -80.0
	add_child(p)
	return p

func _load(track: String, loop_it := true) -> AudioStream:
	var key := "%s|%d" % [track, int(loop_it)]
	if _cache.has(key):
		return _cache[key]
	var path := MUSIC_DIR + track + ".ogg"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	elif FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if stream is AudioStreamOggVorbis:
		stream.loop = loop_it
	_cache[key] = stream
	return stream

## Effective fade-in level: the nominal MUSIC_DB scaled by the user's linear
## music_volume. At/near zero we hard-mute to -80 dB instead of -inf.
func _target_db() -> float:
	return -80.0 if music_volume <= 0.005 else MUSIC_DB + linear_to_db(music_volume)

func _crossfade_to(stream: AudioStream) -> void:
	var prev := _active
	var next := _b if _active == _a else _a
	next.stream = stream
	next.volume_db = -80.0
	next.play()
	_active = next
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(next, "volume_db", _target_db(), FADE)
	tw.tween_property(prev, "volume_db", -80.0, FADE)
	tw.set_parallel(false)
	tw.tween_callback(prev.stop)

## Crossfade to a single looping `track`. No-op if already playing or missing.
func play(track: String) -> void:
	_pl_active = false
	if track != "":
		_wanted = track
		_wanted_list = []
	if not enabled or track == "" or track == _current:
		return
	var stream := _load(track, true)
	if stream == null:
		return
	_current = track
	track_changed.emit(track)
	_crossfade_to(stream)

## Play a list of tracks back-to-back, looping the list forever.
func play_playlist(tracks: Array) -> void:
	if tracks.is_empty():
		return
	_wanted = ""
	_wanted_list = tracks.duplicate()
	if not enabled:
		return
	if _pl_active and _playlist == tracks:
		return
	_playlist = tracks.duplicate()
	_pl_idx = 0
	_pl_active = true
	_current = "__playlist__"
	_play_playlist_track()

func _play_playlist_track() -> void:
	var stream := _load(str(_playlist[_pl_idx]), false)
	if stream == null:
		return
	_crossfade_to(stream)
	track_changed.emit(str(_playlist[_pl_idx]))

func _on_finished(which: AudioStreamPlayer) -> void:
	if not _pl_active or which != _active:
		return
	_pl_idx = (_pl_idx + 1) % _playlist.size()
	_play_playlist_track()

func next_track() -> void:
	if not _pl_active or _playlist.is_empty():
		return
	_pl_idx = (_pl_idx + 1) % _playlist.size()
	_play_playlist_track()

func prev_track() -> void:
	if not _pl_active or _playlist.is_empty():
		return
	_pl_idx = (_pl_idx - 1 + _playlist.size()) % _playlist.size()
	_play_playlist_track()

func current_track() -> String:
	if not _pl_active or _playlist.is_empty():
		return ""
	return str(_playlist[_pl_idx])

func stop() -> void:
	_pl_active = false
	_current = ""
	var tw := create_tween()
	tw.tween_property(_active, "volume_db", -80.0, FADE)
	tw.tween_callback(_active.stop)

## Settings-panel switch: mute fades the music out and remembers the choice;
## unmute resumes whatever the game last asked for.
func set_music_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	if on:
		if not _wanted_list.is_empty():
			play_playlist(_wanted_list.duplicate())
		elif _wanted != "":
			var track := _wanted
			_current = ""
			play(track)
	else:
		stop()
	_save_settings()

## Settings-panel slider: set the music level (linear 0.0–1.0). Applied to the
## playing cue immediately (no crossfade) and remembered.
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	if enabled and _active != null and _active.playing:
		_active.volume_db = _target_db()
	_save_settings()

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("audio", "music", enabled)
	cf.set_value("audio", "volume", music_volume)
	cf.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		enabled = bool(cf.get_value("audio", "music", true))
		music_volume = clampf(float(cf.get_value("audio", "volume", 1.0)), 0.0, 1.0)

## Pick the area track for a room dictionary: an explicit "music" key wins,
## shops get the commerce cue, everything else the chapter's street cue.
func for_room(r: Dictionary) -> String:
	if r.has("music"):
		return str(r["music"])
	if r.has("shop"):
		return "shops"
	return str(CHAPTER_TRACKS.get(GameState.current_chapter, "streets"))
