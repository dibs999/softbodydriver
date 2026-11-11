extends Node3D
## Blue light bar and two-tone siren ("Martinshorn") of an emergency vehicle. The bar sits on the
## model's light bar lens (found when the visual model is attached), held relative to the
## dashboard anchor so it follows the body. Lights flash in the German double-flash pattern,
## alternating left and right; the siren alternates two horn tones a fourth apart.

var vehicle: SBVehicle
## Lens centre and size in car coordinates (x forward, y up, z right), relative to the dashboard.
var offset := Vector3.ZERO
var size := Vector3(0.3, 0.08, 1.1)
var active := false:
	set(value):
		active = value
		if is_inside_tree():
			_apply(0.0)

const BLUE := Color(0.12, 0.35, 1.0)
const TONES := [440.0, 585.0]   # Hz, each held 0.65 s
const TONE_TIME := 0.65

var _lamps: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _on_mat: StandardMaterial3D
var _off_mat: StandardMaterial3D
var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _sample_t := 0.0
var _time := 0.0


func _ready() -> void:
	if not _lamps.is_empty():
		return
	top_level = true
	_on_mat = StandardMaterial3D.new()
	_on_mat.albedo_color = BLUE
	_on_mat.emission_enabled = true
	_on_mat.emission = BLUE
	_on_mat.emission_energy_multiplier = 9.0
	_off_mat = StandardMaterial3D.new()
	_off_mat.albedo_color = Color(0.05, 0.09, 0.22)
	_off_mat.roughness = 0.2
	_off_mat.metallic = 0.1
	for side in 2:
		var lamp := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size.x * 0.9, size.y * 1.05, size.z * 0.42)
		lamp.mesh = box
		lamp.material_override = _off_mat
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(0, 0, (side * 2 - 1) * size.z * 0.27)   # local: x fwd, z right
		add_child(lamp)
		_lamps.append(lamp)
		var light := OmniLight3D.new()
		light.light_color = BLUE
		light.omni_range = 14.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = lamp.position + Vector3.UP * 0.12
		add_child(light)
		_lights.append(light)
	_player = AudioStreamPlayer3D.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.25
	_player.stream = stream
	_player.unit_size = 18.0
	_player.max_db = 3.0
	_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	_player.bus = "Master"
	add_child(_player)
	_apply(0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or _lamps.is_empty():
		return
	var dash_v: Variant = vehicle.get_dashboard_transform()
	if not dash_v is Transform3D:
		return
	var dash: Transform3D = dash_v
	var car: Basis = vehicle.get_visual_basis()   # columns: right, up, -forward
	var right := car.x
	var up := car.y
	var forward := -car.z
	global_transform = Transform3D(Basis(forward, up, right), dash.origin + forward * offset.x + up * offset.y + right * offset.z)
	_time += delta
	_apply(_time)
	if active:
		_fill_siren()


## Double flash per side, sides alternating: each lamp flashes twice for 60 ms within its half of a
## 0.7 s cycle.
static func flash(t: float, side: int) -> bool:
	var c := fposmod(t + side * 0.35, 0.7)
	return c < 0.06 or (c > 0.12 and c < 0.18)


func _apply(t: float) -> void:
	for side in _lamps.size():
		var lit := active and flash(t, side)
		_lamps[side].material_override = _on_mat if lit else _off_mat
		_lights[side].light_energy = 3.5 if lit else 0.0
	if _player:
		if active and not _player.playing:
			_player.play()
			_playback = _player.get_stream_playback()
		elif not active and _player.playing:
			_player.stop()
			_playback = null


func _fill_siren() -> void:
	if _playback == null:
		return
	var rate := 22050.0
	var frames := _playback.get_frames_available()
	for i in frames:
		_sample_t += 1.0 / rate
		var tone: float = TONES[int(_sample_t / TONE_TIME) % 2]
		_phase = fmod(_phase + tone / rate, 1.0)
		# Horn timbre: odd harmonics of a soft square wave, slightly compressed.
		var x := TAU * _phase
		var s := sin(x) + 0.33 * sin(3.0 * x) + 0.18 * sin(5.0 * x) + 0.09 * sin(7.0 * x)
		s = tanh(s * 1.4) * 0.5
		_playback.push_frame(Vector2(s, s))
