extends Node
## Crossfading background-music director (autoload).
##
## Same two-player crossfade design as the original engine. The sequels ship
## soundtrack-light: tracks land in assets/audio/music/<name>.ogg as they're
## produced, and a missing file is a graceful no-op so the scaffold runs silent.

const MUSIC_DIR := "res://assets/audio/music/"
const FADE := 1.2          # crossfade seconds
const MUSIC_DB := -8.0     # nominal playback level

signal track_changed(track)

var enabled := true
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _current := ""
var _cache := {}

func _ready() -> void:
	_a = _make_player()
	_b = _make_player()
	_active = _a

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

func _crossfade_to(stream: AudioStream) -> void:
	var prev := _active
	var next := _b if _active == _a else _a
	next.stream = stream
	next.volume_db = -80.0
	next.play()
	_active = next
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(next, "volume_db", MUSIC_DB, FADE)
	tw.tween_property(prev, "volume_db", -80.0, FADE)
	tw.set_parallel(false)
	tw.tween_callback(prev.stop)

## Crossfade to a single looping `track`. No-op if already playing or missing.
func play(track: String) -> void:
	if not enabled or track == "" or track == _current:
		return
	var stream := _load(track, true)
	if stream == null:
		return
	_current = track
	track_changed.emit(track)
	_crossfade_to(stream)

func stop() -> void:
	_current = ""
	var tw := create_tween()
	tw.tween_property(_active, "volume_db", -80.0, FADE)
	tw.tween_callback(_active.stop)

## Pick the area track for a room dictionary: an explicit "music" key wins,
## shops get the commerce cue, everything else the chapter's street cue.
func for_room(r: Dictionary) -> String:
	if r.has("music"):
		return str(r["music"])
	if r.has("shop"):
		return "shops"
	return "streets"
