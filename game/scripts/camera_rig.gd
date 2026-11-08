extends Camera3D
## Vehicle cameras: chase (spring-damped), hood, cockpit, orbit (mouse), trackside.

enum Mode { CHASE, ORBIT, COCKPIT, HOOD, TRACKSIDE }
const MODE_NAMES := ["Verfolger", "Orbit (Maus)", "Cockpit", "Motorhaube", "Streckenrand"]

var target: SBVehicle
var mode: int = Mode.CHASE
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _look := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.25
var _dist := 7.0
var _dragging := false
var _track_pos := Vector3.ZERO
var shake := 0.0
var look_back := false


func cycle() -> String:
	mode = (mode + 1) % MODE_NAMES.size()
	_track_pos = Vector3.ZERO
	return MODE_NAMES[mode]


func snap() -> void:
	if target == null:
		return
	var fwd := target.get_forward()
	_pos = target.get_chase_target() - fwd * 6.5 + Vector3.UP * 2.0
	_look = target.get_chase_target()
	_vel = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(3.0, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(30.0, _dist * 1.1)
	elif event is InputEventMouseMotion and (_dragging or mode == Mode.ORBIT and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.004, -0.2, 1.3)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tgt := target.get_chase_target()
	var fwd := target.get_forward()
	var up := target.get_up()
	var vel := target.get_velocity()
	var speed := vel.length()
	fov = 62.0
	match mode:
		Mode.CHASE:
			var heading := Vector3(fwd.x, 0, fwd.z).normalized()
			if speed > 3.0 and Vector3(vel.x, 0, vel.z).length() > 1.0:
				# Blend towards the travel direction for a natural drift camera.
				heading = heading.lerp(Vector3(vel.x, 0, vel.z).normalized(), 0.35).normalized()
			if look_back:
				heading = -heading
			var dist := _dist + speed * 0.04
			var desired := tgt - heading.rotated(Vector3.UP, _yaw if _dragging else 0.0) * dist + Vector3.UP * (1.6 + _dist * 0.08)
			# Critically damped spring.
			var k := 28.0
			var c := 2.0 * sqrt(k)
			var acc := (desired - _pos) * k - _vel * c
			_vel += acc * delta
			_pos += _vel * delta
			if _pos.distance_to(desired) > 25.0:
				_pos = desired
			_look = _look.lerp(tgt + Vector3.UP * 0.3, clampf(delta * 12.0, 0.0, 1.0))
			fov = 62.0 + clampf(speed * 0.25, 0.0, 14.0)
			global_position = _pos
			look_at(_look, Vector3.UP)
		Mode.ORBIT:
			var off := Vector3(cos(_yaw) * cos(_pitch), sin(_pitch), sin(_yaw) * cos(_pitch)) * _dist
			global_position = tgt + off
			look_at(tgt, Vector3.UP)
		Mode.COCKPIT:
			var eye := target.get_driver_eye()
			global_position = eye
			var look_dir := -fwd if look_back else fwd
			look_at(eye + look_dir * 10.0 + up * -0.6, up)
			fov = 72.0
		Mode.HOOD:
			var eye2 := target.get_driver_eye() + fwd * 1.2 + up * 0.05
			global_position = eye2
			look_at(eye2 + fwd * 10.0 - up * 0.4, up)
			fov = 70.0
		Mode.TRACKSIDE:
			if _track_pos == Vector3.ZERO or _track_pos.distance_to(tgt) > 60.0:
				var side := target.get_right() * 9.0
				_track_pos = tgt + fwd * 35.0 + side + Vector3.UP * 1.5
			global_position = _track_pos
			look_at(tgt, Vector3.UP)
			fov = clampf(30.0 + _track_pos.distance_to(tgt) * 0.5, 25.0, 60.0)
	if shake > 0.001:
		h_offset = randf_range(-1, 1) * shake * 0.05
		v_offset = randf_range(-1, 1) * shake * 0.05
		shake = maxf(0.0, shake - delta * 3.0)
	else:
		h_offset = 0.0
		v_offset = 0.0
