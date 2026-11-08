extends Node
## Procedural vehicle audio: engine (firing frequency + harmonics + intake noise), tyre squeal,
## wind and crash impacts. Everything is synthesised into one AudioStreamGenerator.

var vehicle: SBVehicle
var cylinders := 4
var redline := 6500.0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _rate := 44100.0
var _phase := 0.0
var _phase2 := 0.0
var _rpm := 800.0
var _load := 0.0
var _squeal := 0.0
var _wind := 0.0
var _crash := 0.0
var _running := true
var _noise_lp := 0.0
var _noise_lp2 := 0.0
var _squeal_phase := 0.0
var _starter := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func impact(strength: float) -> void:
	_crash = minf(1.5, _crash + strength)


func _process(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var t := vehicle.get_telemetry()
	_rpm = lerpf(_rpm, float(t["rpm"]), 0.35)
	_load = lerpf(_load, float(t["throttle"]), 0.2)
	var was_running := _running
	_running = bool(t["running"])
	if _running and not was_running:
		_starter = 0.0
	var slip := 0.0
	var ws := vehicle.get_wheel_slip()
	var wl := vehicle.get_wheel_load()
	for i in ws.size():
		slip = maxf(slip, clampf((ws[i] - 1.5) / 6.0, 0.0, 1.0) * wl[i])
	_squeal = lerpf(_squeal, slip, 0.2)
	_wind = clampf(float(t["speed_kmh"]) / 200.0, 0.0, 1.0)
	_player.volume_db = linear_to_db(maxf(0.0001, Game.settings["master_volume"]))
	_fill()


func _fill() -> void:
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var fire_hz := maxf(_rpm, 0.0) / 60.0 * cylinders * 0.5
	var engine_amp := 0.0
	if _running:
		engine_amp = 0.18 + 0.32 * _load
	elif _rpm > 50.0:
		engine_amp = 0.08 * clampf(_rpm / 800.0, 0.0, 1.0)
	var rough := 0.15 + 0.35 * _load
	var squeal_hz := 820.0 + _squeal * 260.0
	for i in frames:
		_phase = fmod(_phase + fire_hz / _rate, 1.0)
		_phase2 = fmod(_phase2 + fire_hz * 0.5 / _rate, 1.0)
		# Pulse-like combustion waveform with sub-harmonic (uneven firing) and harmonics.
		var p := _phase
		var pulse := exp(-p * 9.0) * 1.6 - 0.25
		var s := pulse * 0.55 + sin(TAU * _phase2) * 0.25 + sin(TAU * _phase * 2.0) * 0.12
		var n := randf() * 2.0 - 1.0
		_noise_lp = lerpf(_noise_lp, n, 0.25)
		_noise_lp2 = lerpf(_noise_lp2, n, 0.04)
		var eng := (s + _noise_lp * rough) * engine_amp
		_squeal_phase = fmod(_squeal_phase + squeal_hz / _rate, 1.0)
		var sq := (sin(TAU * _squeal_phase) * 0.6 + _noise_lp * 0.4) * _squeal * 0.35
		var wind := _noise_lp2 * _wind * 0.5
		var crash := 0.0
		if _crash > 0.001:
			crash = (n * 0.7 + _noise_lp2 * 2.0) * minf(_crash, 1.0) * 0.8
			_crash *= 0.99985
		var v := clampf(eng + sq + wind + crash, -1.0, 1.0)
		_playback.push_frame(Vector2(v, v))
