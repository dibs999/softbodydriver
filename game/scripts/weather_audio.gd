extends Node
## Original procedural rainfall: no recordings or external assets; one bounded generator buffer.
## One generator routes through Master. Camera shelter filters the rain; paused simulation
## pauses playback. Pitch follows slow motion, while master volume can mute exactly.
const MIX_RATE := 24000
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _target_level := 0.0
var _level := 0.0
var _target_occlusion := 0.0
var _occlusion := 0.0
var _target_roof := 0.0
var _roof := 0.0
var _master := 0.8
var _paused := false
var _low := Vector2.ZERO
var _mid := Vector2.ZERO
var _filtered := Vector2.ZERO
var _drop := 0.0
var _drop_phase := 0.0
var _drop_hz := 1200.0
var _drop_pan := 0.0
var _time := 0.0

func _ready() -> void:
	_rng.seed = 60917
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.name = "RainAmbience"
	_player.bus = &"Master"
	_player.stream = generator
	add_child(_player)

func _exit_tree() -> void:
	if is_instance_valid(_player): _player.stop()
	_playback = null

func set_conditions(rain: float, paused: bool, time_scale: float, cabin: bool, canopy: bool, master: float) -> void:
	_target_level = clampf(rain, 0, 1)
	_target_occlusion = 0.90 if cabin else (0.58 if canopy else 0.0)
	_target_roof = 0.65 if canopy else (0.36 if cabin else 0.0)
	_master = clampf(master, 0, 1)
	_paused = paused or time_scale <= 0
	if is_instance_valid(_player):
		_player.stream_paused = _paused
		_player.pitch_scale = clampf(time_scale, 0.1, 2.0)
		# Silence queued samples immediately when the master slider reaches zero.
		_player.volume_linear = 0.0 if _master == 0 else 1.0

func _process(_delta: float) -> void:
	if _paused: return
	if _target_level > 0 and _master > 0 and not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback()
	if _playback == null: return
	if _target_level == 0 and _level < 0.0001:
		_player.stop()
		_playback = null
		return
	var frames := _playback.get_frames_available()
	if frames > 0: _playback.push_buffer(render_frames(frames))

func render_frames(count: int) -> PackedVector2Array:
	## The live mixer and PCM regression/export use this identical synthesis path.
	var frames := PackedVector2Array()
	frames.resize(count)
	if _paused: return frames
	for i in count:
		_level = lerpf(_level, _target_level, 0.00020)
		_occlusion = lerpf(_occlusion, _target_occlusion, 0.00028)
		_roof = lerpf(_roof, _target_roof, 0.00028)
		_time += 1.0 / MIX_RATE
		var noise := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		_low += (noise - _low) * 0.025
		_mid += (noise - _mid) * 0.32
		var gust := 0.86 + sin(_time * 0.73) * 0.08 + sin(_time * 0.19) * 0.06
		var rain := ((noise - _low) * 0.13 + _mid * 0.085 + _low * 0.03) * gust
		_filtered += (rain - _filtered) * lerpf(0.70, 0.07, _occlusion)
		if _rng.randf() < 0.00075:
			_drop = _rng.randf_range(0.15, 1)
			_drop_hz = _rng.randf_range(650, 1900)
			_drop_pan = _rng.randf_range(-0.8, 0.8)
		_drop *= 0.992
		_drop_phase = fmod(_drop_phase + TAU * _drop_hz / MIX_RATE, TAU)
		var tap := sin(_drop_phase) * _drop * lerpf(0.012, 0.12, _roof)
		var mixed :=  _filtered * lerpf(1.0, 0.55, _occlusion) + Vector2(tap * (1 - _drop_pan), tap * (1 + _drop_pan))
		frames[i] = mixed * _level * _master * 0.65
	return frames
