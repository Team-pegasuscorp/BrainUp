extends Node
## Sound effects, synthesised at startup so the project ships no audio files.
## Every effect is a short list of notes rendered into an AudioStreamWAV.

const MIX_RATE := 22050
const POOL_SIZE := 8

const C4 := 261.63
const E4 := 329.63
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25
const E5 := 659.25
const G5 := 783.99
const A5 := 880.0
const C6 := 1046.5
const E6 := 1318.5

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_build_library()


## `pitch` rescales the effect (used to make combo hits climb); `volume_scale` is linear.
func play(sound: String, pitch: float = 1.0, volume_scale: float = 1.0) -> void:
	if not SaveManager.sound_enabled or not _streams.has(sound):
		return
	var volume := SaveManager.sound_volume * volume_scale
	if volume <= 0.001:
		return
	var player := _free_player()
	player.stream = _streams[sound]
	player.pitch_scale = pitch
	player.volume_db = linear_to_db(volume)
	player.play()


func stop_all() -> void:
	for player in _players:
		player.stop()


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]


func _build_library() -> void:
	_streams["click"] = _render([_note(1300.0, 0.05, 0.0, 0.35, 850.0)])
	_streams["tick"] = _render([_note(1900.0, 0.035, 0.0, 0.3)])
	_streams["tick_soft"] = _render([_note(1100.0, 0.025, 0.0, 0.22)])
	_streams["thud"] = _render([_note(120.0, 0.2, 0.0, 0.9, 45.0)])
	_streams["correct"] = _render([
		_note(E5, 0.09, 0.0, 0.45, 0.0, true),
		_note(A5, 0.2, 0.08, 0.5, 0.0, true),
	])
	_streams["wrong"] = _render([_note(230.0, 0.3, 0.0, 0.4, 130.0, false, "square")])
	_streams["timeout"] = _render([
		_note(210.0, 0.12, 0.0, 0.35, 0.0, false, "tri"),
		_note(150.0, 0.24, 0.13, 0.35, 0.0, false, "tri"),
	])
	_streams["victory"] = _render([
		_note(C5, 0.12, 0.0, 0.45, 0.0, true),
		_note(E5, 0.12, 0.11, 0.45, 0.0, true),
		_note(G5, 0.12, 0.22, 0.45, 0.0, true),
		_note(C6, 0.55, 0.33, 0.55, 0.0, true),
	])
	_streams["defeat"] = _render([
		_note(G4, 0.22, 0.0, 0.4, 0.0, false, "tri"),
		_note(E4, 0.22, 0.2, 0.4, 0.0, false, "tri"),
		_note(C4, 0.5, 0.4, 0.45, 0.0, false, "tri"),
	])
	_streams["level_up"] = _render([
		_note(C5, 0.1, 0.0, 0.4, 0.0, true),
		_note(E5, 0.1, 0.07, 0.4, 0.0, true),
		_note(G5, 0.1, 0.14, 0.4, 0.0, true),
		_note(C6, 0.1, 0.21, 0.4, 0.0, true),
		_note(E6, 0.6, 0.28, 0.5, 0.0, true),
	])
	_streams["achievement"] = _render([
		_note(G5, 0.09, 0.0, 0.4, 0.0, true),
		_note(C6, 0.35, 0.09, 0.5, 0.0, true),
	])
	_streams["xp_fill"] = _render([_note(320.0, 0.7, 0.0, 0.16, 960.0)])


func _note(
	freq: float,
	duration: float,
	start: float = 0.0,
	volume: float = 0.5,
	slide_to: float = 0.0,
	bell: bool = false,
	wave: String = "sine",
) -> Dictionary:
	return {
		"freq": freq, "dur": duration, "start": start, "vol": volume,
		"slide_to": slide_to, "bell": bell, "wave": wave,
	}


func _render(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for note in notes:
		total = maxf(total, float(note["start"]) + float(note["dur"]))
	var frames := int(total * MIX_RATE) + 1
	var mix := PackedFloat32Array()
	mix.resize(frames)

	for note in notes:
		var first := int(float(note["start"]) * MIX_RATE)
		var length := int(float(note["dur"]) * MIX_RATE)
		var f0: float = note["freq"]
		var f1: float = note["slide_to"] if float(note["slide_to"]) > 0.0 else f0
		var phase := 0.0
		for i in length:
			if first + i >= frames:
				break
			var progress := float(i) / float(length)
			phase += (lerpf(f0, f1, progress) / MIX_RATE) * TAU
			var sample := _wave(phase, str(note["wave"]), bool(note["bell"]))
			## Short attack (no click) then a smooth fade-out.
			var envelope := minf(float(i) / (0.004 * MIX_RATE), 1.0) * pow(1.0 - progress, 1.6)
			mix[first + i] += sample * envelope * float(note["vol"])

	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		bytes.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _wave(phase: float, kind: String, bell: bool) -> float:
	var value := 0.0
	match kind:
		"square":
			## Rounded square: fundamental plus odd harmonics, harsh but not piercing.
			value = sin(phase) + sin(phase * 3.0) / 3.0 + sin(phase * 5.0) / 5.0
			value *= 0.6
		"tri":
			value = asin(sin(phase)) * (2.0 / PI)
		_:
			value = sin(phase)
	if bell:
		value += sin(phase * 2.0) * 0.3 + sin(phase * 3.0) * 0.1
		value /= 1.3
	return value
