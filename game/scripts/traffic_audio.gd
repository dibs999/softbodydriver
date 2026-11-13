extends Node3D
## Sound of the other cars (traffic, race opponents, police): the nearest few within earshot get a
## 3D engine from the same recordings as the player's car - load and coast loops crossfaded by rpm
## and throttle - and a tyre roar that grows with speed, both with Doppler. Without it every other
## car on the map was silent. The Doppler shift is applied here: Godot's own is overwritten by any
## pitch_scale set each frame, and both voices follow the rpm and speed every frame.

const VehicleAudio := preload("res://scripts/vehicle_audio.gd")
const MAX_CARS := 4
const RANGE := 160.0          # m; beyond this a car is not given a voice
const ROAD_RATE := 22050

var game: Node3D
var emitters := {}            # SBVehicle -> {"root", "engine": [players], "rpms", "coast_from", "road", "gains"}
var _road_stream: AudioStreamWAV
var _ear := Vector3.ZERO
var _ear_velocity := Vector3.ZERO
const SOUND_SPEED := 343.0


func _ready() -> void:
	_road_stream = _make_road_noise()


## Tyre roar: a second of low-passed noise, looped; its pitch follows the speed.
static func _make_road_noise() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var data := PackedByteArray()
	data.resize(ROAD_RATE * 2)
	var low := 0.0
	var mid := 0.0
	for i in ROAD_RATE:
		var n := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, n, 0.05)
		mid = lerpf(mid, n, 0.3)
		var s := clampf(low * 2.4 + (mid - low) * 0.5, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = ROAD_RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = ROAD_RATE
	return w


func _process(delta: float) -> void:
	if not game or not is_instance_valid(game.get("cam")):
		return
	var ear: Vector3 = game.cam.global_position
	if delta > 0.0:
		_ear_velocity = _ear_velocity.lerp((ear - _ear) / delta, 1.0 - exp(-delta * 10.0))
	_ear = ear
	# The nearest others within range get (or keep) a voice.
	var near: Array = []
	for v: SBVehicle in game.vehicles:
		if not is_instance_valid(v) or v == game.player:
			continue
		var d := v.get_position_ws().distance_to(ear)
		if d < RANGE:
			near.append([d, v])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for k in mini(MAX_CARS, near.size()):
		keep[near[k][1]] = true
	for v in emitters.keys():
		if not keep.has(v) or not is_instance_valid(v):
			emitters[v]["root"].queue_free()
			emitters.erase(v)
	var paused: bool = game.world.paused
	var volume := float(Game.settings.get("master_volume", 1.0))
	var engine_volume := volume * float(Game.settings.get("engine_volume", 0.8))
	for v: SBVehicle in keep:
		if not emitters.has(v):
			emitters[v] = _make_emitter(v)
		_update(v, emitters[v], delta, paused, engine_volume, volume)


func _make_emitter(v: SBVehicle) -> Dictionary:
	var cyl := int(v.get_info().get("cylinders", 4))
	var profile := "v8" if cyl == 8 else ("v6" if cyl == 6 else "i4")
	var load_rpms: Array = VehicleAudio.ENGINE_BANDS[profile]
	var coast_rpms: Array = VehicleAudio.COAST_BANDS[profile]
	var root_node := Node3D.new()
	add_child(root_node)
	var players: Array[AudioStreamPlayer3D] = []
	# An electric car in traffic is heard by its tyres alone.
	var rpms: Array = [] if cyl <= 0 else load_rpms + coast_rpms
	for i in rpms.size():
		var state := "load" if i < load_rpms.size() else "coast"
		var source: AudioStreamWAV = load(VehicleAudio.RECORDINGS + "%s_%s_%d.wav" % [profile, state, rpms[i]])
		var p := AudioStreamPlayer3D.new()
		if source:
			var loop := source.duplicate() as AudioStreamWAV
			loop.loop_end = roundi(source.get_length() * source.mix_rate)
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			p.stream = loop
		_setup_3d(p, 7.0)
		root_node.add_child(p)
		if p.stream:
			p.play(randf() * 0.5)
		players.append(p)
	var road := AudioStreamPlayer3D.new()
	road.stream = _road_stream
	_setup_3d(road, 5.0)
	root_node.add_child(road)
	road.play(randf())
	var gains := PackedFloat32Array()
	gains.resize(players.size())
	return {"root": root_node, "engine": players, "rpms": rpms, "coast_from": load_rpms.size(),
		"load_rpms": load_rpms, "coast_rpms": coast_rpms, "road": road, "gains": gains, "rpm": 800.0, "load": 0.0, "doppler": 1.0}


static func _setup_3d(p: AudioStreamPlayer3D, unit: float) -> void:
	p.unit_size = unit
	p.max_distance = RANGE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED   # applied in _update
	p.volume_db = -80.0


func _update(v: SBVehicle, e: Dictionary, delta: float, paused: bool, engine_volume: float, volume: float) -> void:
	var root_node: Node3D = e["root"]
	root_node.global_position = v.get_position_ws() + v.get_up() * 0.5
	var t := v.get_telemetry()
	var running := bool(t.get("running", false))
	var rpm := maxf(0.0, float(t.get("rpm", 0.0)))
	e["rpm"] = lerpf(float(e["rpm"]), rpm, 1.0 - exp(-delta * 20.0))
	var demand := float(t.get("throttle", 0.0)) if running else 0.0
	e["load"] = lerpf(float(e["load"]), demand, 1.0 - exp(-delta * 9.0))
	var r := float(e["rpm"])
	# Doppler: f' = f (c + v_ear towards the car) / (c - v_car towards the ear).
	var to_ear := _ear - root_node.global_position
	var dist := to_ear.length()
	var doppler := 1.0
	if dist > 0.5:
		var dir := to_ear / dist
		doppler = clampf((SOUND_SPEED - _ear_velocity.dot(dir)) / maxf(40.0, SOUND_SPEED - v.get_velocity().dot(dir)), 0.6, 1.6)
	e["doppler"] = doppler
	var l := float(e["load"])
	var coast := (1.0 - smoothstep(0.04, 0.38, l)) * smoothstep(1000.0, 1600.0, r)
	var level := (1.0 if running else 0.0) * engine_volume * lerpf(0.35, 1.0, l)
	var players: Array = e["engine"]
	var gains: PackedFloat32Array = e["gains"]
	var coast_from := int(e["coast_from"])
	for i in players.size():
		var p: AudioStreamPlayer3D = players[i]
		p.stream_paused = paused
		var is_coast := i >= coast_from
		var w := VehicleAudio._band_weight(e["coast_rpms"] if is_coast else e["load_rpms"], i - coast_from if is_coast else i, r)
		w *= coast if is_coast else 1.0 - coast
		gains[i] = lerpf(gains[i], level * w, 1.0 - exp(-delta * 15.0))
		p.volume_db = linear_to_db(maxf(0.0001, gains[i]))
		p.pitch_scale = clampf(r / float(e["rpms"][i]), 0.45, 3.8) * doppler
	e["gains"] = gains
	var speed := absf(v.get_speed_kmh())
	var road: AudioStreamPlayer3D = e["road"]
	road.stream_paused = paused
	road.volume_db = linear_to_db(maxf(0.0001, volume * 0.55 * smoothstep(5.0, 120.0, speed)))
	road.pitch_scale = clampf(0.6 + speed / 110.0, 0.6, 2.2) * doppler


## Sum of the engine gains of a car (0 when it has no voice): for tests.
func engine_level(v: SBVehicle) -> float:
	if not emitters.has(v):
		return 0.0
	var s := 0.0
	for g in emitters[v]["gains"]:
		s += g
	return s
