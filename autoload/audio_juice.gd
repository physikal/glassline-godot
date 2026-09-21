extends Node
## Soft attack stingers from server result flags. Zero combat / Marks / API.
## Toy-spy clicks — mute anytime. Hunt stays fully readable silent.

const Contract := preload("res://types/contract.gd")

const STORE := "user://glassline_settings.json"

var store_path: String = STORE
var muted: bool = false
var last_cues: PackedStringArray = PackedStringArray()
var last_played: PackedStringArray = PackedStringArray()

var _fp: String = ""
var _player: AudioStreamPlayer


func _ready() -> void:
	_load()
	if OS.get_environment("GLASSLINE_MUTE") == "1":
		muted = true
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


func set_muted(on: bool) -> void:
	muted = on
	_save()
	if muted and _player != null and _player.playing:
		_player.stop()


func cues_for(last: Dictionary) -> PackedStringArray:
	## A1: hit / miss / HG / brush from attack result flags only.
	var cues := PackedStringArray()
	if str(last.get("type", "")) != Contract.ACT_ATTACK:
		return cues
	if bool(last.get("decoyCleared", false)) or not bool(last.get("hit", false)):
		cues.append(Contract.CUE_MISS)
	else:
		cues.append(Contract.CUE_HIT)
	if last.has("highGroundApplied") and bool(last.get("highGroundApplied")):
		cues.append(Contract.CUE_HIGH)
	if last.has("coverApplied") and bool(last.get("coverApplied")):
		cues.append(Contract.CUE_BRUSH)
	return cues


func notice_last_action(last: Dictionary) -> PackedStringArray:
	## Deduped play. Mute skips audio; cues still resolve for chrome tests.
	last_cues = cues_for(last)
	var fp := _fingerprint(last)
	if fp == "" or fp == _fp:
		last_played = PackedStringArray()
		return last_cues
	_fp = fp
	if muted or last_cues.is_empty():
		last_played = PackedStringArray()
		return last_cues
	play_cues(last_cues)
	last_played = last_cues.duplicate()
	return last_cues


func play_cues(cues: PackedStringArray) -> void:
	if muted or cues.is_empty():
		return
	if _player == null:
		return
	_player.stream = _mix(cues)
	_player.volume_db = -8.0
	_player.play()


func _fingerprint(last: Dictionary) -> String:
	if last.is_empty() or str(last.get("type", "")) == "":
		return ""
	return "%s|%s|%s|%s|%s|%s" % [
		str(last.get("type", "")),
		str(last.get("hit", "")),
		str(last.get("decoyCleared", "")),
		str(last.get("highGroundApplied", "")),
		str(last.get("coverApplied", "")),
		str(last.get("hitChance", "")),
	]


func _mix(cues: PackedStringArray) -> AudioStreamWAV:
	## Short synthesized clicks. No sample packs.
	var rate := 22050
	var msec := 140
	var n := int(rate * msec / 1000.0)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := _env(t, float(msec) / 1000.0)
		var s := 0.0
		for cue in cues:
			s += _sample(str(cue), t) * 0.42
		var sample := int(clampf(s * env, -1.0, 1.0) * 22000.0)
		pcm[i * 2] = sample & 0xFF
		pcm[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = pcm
	return stream


func _env(t: float, dur: float) -> float:
	var attack := 0.008
	var release := dur * 0.55
	if t < attack:
		return t / attack
	if t > dur - release:
		return maxf(0.0, (dur - t) / release)
	return 1.0


func _sample(cue: String, t: float) -> float:
	match cue:
		Contract.CUE_HIT:
			return sin(TAU * 1240.0 * t) * 0.72 + sin(TAU * 1860.0 * t) * 0.22
		Contract.CUE_MISS:
			return sin(TAU * 420.0 * t) * 0.55 * (1.0 if t < 0.045 else 0.0)
		Contract.CUE_HIGH:
			return sin(TAU * 1760.0 * t) * 0.38 + sin(TAU * 2340.0 * t) * 0.16
		Contract.CUE_BRUSH:
			return sin(TAU * 180.0 * t) * 0.22 + sin(TAU * 90.0 * t) * 0.18
		_:
			return 0.0


func _load() -> void:
	if not FileAccess.file_exists(store_path):
		return
	var file := FileAccess.open(store_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		muted = bool(parsed.get("muted", false))


func _save() -> void:
	var file := FileAccess.open(store_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"muted": muted}))
	file.close()
