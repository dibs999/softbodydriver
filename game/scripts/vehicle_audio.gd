extends Node
## Recorded engine loops and gear changes, plus procedural road, wind and impacts.

const MIX_RATE := 32000.0
const RECORDINGS := "res://audio/engine/"
const ENGINE_BANDS := {
	"i4": [780, 2000, 2850, 4100, 5100, 6300],
	"v6": [940, 1400, 2000],
	"v8": [845, 2150, 3200, 4400, 4750],
}
const COAST_BANDS := {"i4": [780, 2500, 3900, 4800], "v6": [940, 1250, 1800], "v8": [845, 3150]}

var vehicle: SBVehicle
var world: SBWorld
var dirt := false
var _loose_road := 0.0
var cockpit := false

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _buffer := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _scrub_phase := 0.0
var _rpm := 0.0
var _load := 0.0
var _engine_level := 0.0
var _engine_bus: StringName
var _engine_filter: AudioEffectLowPassFilter
var _engine_profile := ""
var _engine_rpms: Array = []
var _coast_rpms: Array = []
var _loop_rpms: Array = []
var _engine_players: Array[AudioStreamPlayer] = []
var _source_gains := PackedFloat32Array()
var _shift_player: AudioStreamPlayer
var _shift_up_sound: AudioStreamWAV
var _shift_down_sound: AudioStreamWAV
var _scrub := 0.0
var _rolling := 0.0
var _wind := 0.0
var _impact := 0.0
var _impact_tail := 0.0
var _gear := 0
var _air_noise := 0.0
var _low_noise := 0.0
var _gravel := 0.0
var _cabin_l := 0.0
var _cabin_r := 0.0
var _grind := 0.0
var _flat := 0.0
var _flat_phase := 0.0
var _wheel_hz := 0.0
var _filter_cutoff := 1800.0
## Two-tone horn (~405 / 507 Hz, soft-clipped), heard through the same cabin filter as the road.
var horn := false
var _horn_level := 0.0
var _horn_p1 := 0.0
var _horn_p2 := 0.0


func _ready() -> void:
	_engine_bus = StringName("Engine %d" % get_instance_id())
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, _engine_bus)
	_engine_filter = AudioEffectLowPassFilter.new()
	AudioServer.add_bus_effect(bus, _engine_filter)
	_shift_player = AudioStreamPlayer.new()
	add_child(_shift_player)
	_shift_up_sound = load(RECORDINGS + "shift_up.wav")
	_shift_down_sound = load(RECORDINGS + "shift_down.wav")

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.18
	_player = AudioStreamPlayer.new()
	_player.stream = generator
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


func _exit_tree() -> void:
	var bus := AudioServer.get_bus_index(_engine_bus)
	if bus > 0:
		AudioServer.remove_bus(bus)


func configure(next_vehicle: SBVehicle, cylinders: int) -> void:
	vehicle = next_vehicle
	var telemetry := vehicle.get_telemetry()
	_gear = telemetry["gear"]
	_rpm = telemetry["rpm"]
	_shift_player.stop()
	var profile := "v8" if cylinders == 8 else ("v6" if cylinders == 6 else "i4")
	if profile == _engine_profile:
		return
	_engine_profile = profile
	for player in _engine_players:
		player.stop()
		player.queue_free()
	_engine_players.clear()
	_source_gains.clear()
	_engine_rpms = ENGINE_BANDS[profile]
	_coast_rpms = COAST_BANDS[profile]
	_loop_rpms = _engine_rpms + _coast_rpms
	for i in _loop_rpms.size():
		var rpm: int = _loop_rpms[i]
		var state := "load" if i < _engine_rpms.size() else "coast"
		var source: AudioStreamWAV = load(RECORDINGS + "%s_%s_%d.wav" % [profile, state, rpm])
		var player := AudioStreamPlayer.new()
		if source:
			var loop := source.duplicate() as AudioStreamWAV
			loop.loop_end = roundi(source.get_length() * source.mix_rate)
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			player.stream = loop
		player.bus = _engine_bus
		player.volume_db = -80.0
		add_child(player)
		_engine_players.append(player)
		_source_gains.append(0.0)
		# Keep the recordings phase-continuous when crossing an RPM band.
		if player.stream:
			player.play()


var _rod_broken := false


func impact(strength: float) -> void:
	_impact = clampf(_impact + strength, 0.0, 1.0)
	_impact_tail = clampf(_impact_tail + strength * 0.7, 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or _playback == null:
		return
	var paused := is_instance_valid(world) and world.paused
	_player.stream_paused = paused
	_shift_player.stream_paused = paused
	for source in _engine_players:
		source.stream_paused = paused
	if paused:
		return
	var t := vehicle.get_telemetry()
	# A thrown connecting rod is a loud bang from the engine bay.
	var rod := bool(t.get("rod_broken", false))
	if rod and not _rod_broken:
		impact(0.85)
	_rod_broken = rod
	var gear: int = t["gear"]
	var slip := 0.0
	var grip := 0.0
	var wheel_slip := vehicle.get_wheel_slip()
	var wheel_load := vehicle.get_wheel_load()
	var effects := vehicle.get_node_or_null("VehicleEffects")
	var loose := 0.0
	if effects:
		for i in mini(4, wheel_load.size()):
			if effects.wheel_surfaces[i] in ["sand", "gravel", "grass"]:
				loose += wheel_load[i] * 0.25
	else:
		loose = 1.0 if dirt else 0.0
	_loose_road = lerpf(_loose_road, clampf(loose, 0, 1), 1.0 - exp(-delta * 8.0))
	for i in mini(wheel_slip.size(), wheel_load.size()):
		slip = maxf(slip, smoothstep(2.4, 9.0, wheel_slip[i]) * wheel_load[i])
		grip = maxf(grip, wheel_load[i])
	var speed := absf(float(t["speed_kmh"]))
	_grind = float(t.get("gear_grind", 0.0))
	_flat = 0.0
	for pressure: float in t["tire_pressure"]:
		_flat = maxf(_flat, 1.0 - smoothstep(2.0, 12.0, pressure))
	_flat *= smoothstep(3.0, 35.0, speed) * grip
	_wheel_hz = speed / 3.6 / 2.0
	var blend := 1.0 - exp(-delta * 12.0)
	_scrub = lerpf(_scrub, slip, blend)
	_rolling = lerpf(_rolling, smoothstep(1.0, 115.0, speed) * grip, blend)
	_wind = lerpf(_wind, smoothstep(18.0, 220.0, speed), blend)
	var volume: float = Game.settings["master_volume"]
	_player.volume_db = linear_to_db(maxf(0.0001, volume * 0.78))
	if gear != _gear and gear > 0 and _gear > 0 and speed > 5.0:
		_shift_player.stream = _shift_up_sound if gear > _gear else _shift_down_sound
		var click_gain := 0.14 if vehicle.is_automatic() else 0.32
		_shift_player.volume_db = linear_to_db(maxf(0.0001, volume * click_gain * (1.0 if cockpit else 0.55)))
		_shift_player.play()
	_gear = gear
	_update_engine(t, volume * float(Game.settings.get("engine_volume", 0.8)), delta)
	_fill()


func _update_engine(telemetry: Dictionary, volume: float, delta: float) -> void:
	var running: bool = telemetry["running"]
	var rpm := maxf(0.0, float(telemetry["rpm"]))
	var throttle: float = telemetry["throttle"] if running else 0.0
	var clutch: float = telemetry["clutch"]
	_rpm = lerpf(_rpm, rpm, 1.0 - exp(-delta * 29.0))
	# Use the simulation's torque interruption, including manual gear changes.
	var changing := float(telemetry.get("shift_remaining", 0.0)) > 0.0
	var demand := throttle * lerpf(0.42, 1.0, clutch)
	if changing:
		demand *= 0.12
	if bool(telemetry.get("tcs_active", false)):
		demand *= 0.55
	_load = lerpf(_load, demand, 1.0 - exp(-delta * (22.0 if demand < _load else 9.0)))
	_engine_level = lerpf(_engine_level, 1.0 if running else smoothstep(90.0, 650.0, rpm) * 0.20, 1.0 - exp(-delta * 20.0))
	var cutoff := lerpf(1100.0, 6400.0, _load) * (0.58 if cockpit else 1.0)
	_filter_cutoff = lerpf(_filter_cutoff, cutoff, 1.0 - exp(-delta * 9.0))
	_engine_filter.cutoff_hz = _filter_cutoff

	# A separate release recording supplies the off-throttle timbre, rather than
	# lowering the volume of the same accelerating engine. Idle uses one voice.
	var coast := (1.0 - smoothstep(0.04, 0.38, _load)) * smoothstep(1000, 1600, _rpm)
	var level := _engine_level * volume * lerpf(0.34, 0.95, _load) * (0.80 if cockpit else 1.0)
	for i in _engine_players.size():
		var player := _engine_players[i]
		var is_coast := i >= _engine_rpms.size()
		var index := i - _engine_rpms.size() if is_coast else i
		var weight := _band_weight(_coast_rpms if is_coast else _engine_rpms, index, _rpm)
		weight *= coast if is_coast else 1.0 - coast
		_source_gains[i] = lerpf(_source_gains[i], level * weight, 1.0 - exp(-delta * 18.0))
		var gain := _source_gains[i]
		player.volume_db = linear_to_db(maxf(0.0001, gain))
		if player.stream:
			player.pitch_scale = clampf(_rpm / float(_loop_rpms[i]), 0.45, 3.8)


static func _band_weight(bands: Array, index: int, rpm: float) -> float:
	var upper := 0
	while upper < bands.size() - 1 and rpm > bands[upper]: upper += 1
	var lower := maxi(0, upper - 1)
	var blend := smoothstep(bands[lower], bands[upper], rpm) if upper > lower else 0.0
	return (1.0 - blend) if index == lower else (blend if index == upper else 0.0)


func _fill() -> void:
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	_buffer.resize(frames)
	var scrub_step := TAU * (410.0 + _scrub * 260.0) / MIX_RATE
	var gravel_chance := 0.004 + _rolling * 0.019
	var filter := 0.12 if cockpit else 0.65
	var road_volume := 0.67 if cockpit else 1.0
	for i in frames:
		var noise := _rng.randf_range(-1.0, 1.0)
		_air_noise = lerpf(_air_noise, noise, 0.12)
		_low_noise = lerpf(_low_noise, noise, 0.025)

		_scrub_phase = fmod(_scrub_phase + scrub_step * (1.0 + 0.06 * _air_noise), TAU)
		if absf(noise) < gravel_chance:
			_gravel = _rng.randf_range(-1.0, 1.0)
		_gravel *= 0.93
		var loose_tire := (_air_noise * 0.23 + _gravel * 0.20) * (_rolling * 0.72 + _scrub * 0.42)
		var road_tire := _air_noise * _rolling * 0.115 + (sin(_scrub_phase) * 0.056 + _air_noise * 0.17) * _scrub
		var tire := lerpf(road_tire, loose_tire, _loose_road)
		var air := (_low_noise * 0.19 + _air_noise * 0.048) * _wind
		var hit := _low_noise * _impact * 2.3 + (_air_noise * 0.7 + noise * 0.2) * _impact_tail
		_flat_phase = fmod(_flat_phase + TAU * _wheel_hz / MIX_RATE, TAU)
		var flap := pow(maxf(0.0, sin(_flat_phase)), 12.0) * _flat * (_low_noise * 0.7 + _air_noise * 0.16)
		var grind := (noise - _air_noise) * _grind * 0.13
		_impact *= 0.9989
		_impact_tail *= 0.9998
		_horn_level = move_toward(_horn_level, 1.0 if horn else 0.0, 1.0 / (0.012 * MIX_RATE) if horn else 1.0 / (0.07 * MIX_RATE))
		var honk := 0.0
		if _horn_level > 0.0:
			_horn_p1 = fmod(_horn_p1 + TAU * 405.0 / MIX_RATE, TAU)
			_horn_p2 = fmod(_horn_p2 + TAU * 507.0 / MIX_RATE, TAU)
			honk = (sin(_horn_p1) + 0.33 * sin(3.0 * _horn_p1) + sin(_horn_p2) + 0.3 * sin(3.0 * _horn_p2)) * 0.15 * _horn_level
		var common := (air + tire + flap + grind) * road_volume + hit + honk
		var spread := (_air_noise - _low_noise) * _wind * 0.065 * road_volume
		_cabin_l = lerpf(_cabin_l, common + spread, filter)
		_cabin_r = lerpf(_cabin_r, common - spread, filter)
		_buffer[i] = Vector2(clampf(_cabin_l, -0.96, 0.96), clampf(_cabin_r, -0.96, 0.96))
	_playback.push_buffer(_buffer)
