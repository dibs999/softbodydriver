extends Camera3D
## Vehicle cameras: chase (spring-damped), hood, cockpit, orbit (mouse), trackside.

enum Mode { CHASE, ORBIT, COCKPIT, HOOD, TRACKSIDE }
const MODE_NAMES := ["Verfolger", "Orbit (Maus)", "Cockpit", "Motorhaube", "Streckenrand"]
const Instruments := preload("res://scripts/instrument_cluster.gd")

var equipment: Node
var target: SBVehicle
var mode: int = Mode.CHASE
var _chase_offset := Vector3.ZERO
var _vel := Vector3.ZERO
var _look_offset := Vector3.UP * 0.3
var _speed_effect := 0.0
var _chase_ready := false
var _yaw := 0.0
var _pitch := 0.25
var _dist := 7.0
var _chase_dist := 5.8
var _dragging := false
var _track_pos := Vector3.ZERO
var _cockpit_ready := false
var _dashboard: Node3D
var _instruments: Control
var _instrument_viewport: SubViewport
var _instrument_car: SBVehicle
var _instrument_time := 0.0
var _center_viewport: SubViewport
var _center_display: Control
var _center_mesh: MeshInstance3D
var _shake_phase := 0.0
var shake := 0.0
var look_back := false
var _cockpit_yaw := 0.0
var _cockpit_pitch := 0.0
var mirrors: Node


func _ready() -> void:
	mirrors = preload("res://scripts/vehicle_mirrors.gd").new()
	mirrors.name = "VehicleMirrors"
	add_child(mirrors)
	_dashboard = Node3D.new()
	_dashboard.name = "Dashboard"
	_dashboard.top_level = true
	_dashboard.hide()
	add_child(_dashboard)
	_instrument_viewport = SubViewport.new()
	_instrument_viewport.size = Instruments.RESOLUTION
	_instrument_viewport.disable_3d = true
	_instrument_viewport.transparent_bg = true
	_instrument_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_dashboard.add_child(_instrument_viewport)
	_instruments = Instruments.new()
	_instrument_viewport.add_child(_instruments)
	var panel := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.32, 0.091)
	panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _instrument_viewport.get_texture()
	panel.material_override = mat
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dashboard.add_child(panel)
	_center_viewport = SubViewport.new()
	_center_viewport.size = Vector2i(512, 280)
	_center_viewport.disable_3d = true
	_center_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_dashboard.add_child(_center_viewport)
	_center_display = preload("res://scripts/cabin_display.gd").new()
	_center_viewport.add_child(_center_display)
	_center_mesh = MeshInstance3D.new()
	var screen := QuadMesh.new()
	screen.size = Vector2(0.235, 0.128)
	_center_mesh.mesh = screen
	_center_mesh.position = Vector3(0.385, -0.055, 0.030)
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_texture = _center_viewport.get_texture()
	_center_mesh.material_override = screen_mat
	_center_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dashboard.add_child(_center_mesh)


func _update_dashboard(delta: float) -> void:
	var anchor: Variant = target.get_dashboard_transform() if mode == Mode.COCKPIT else null
	var opening := not _dashboard.visible
	_dashboard.visible = anchor is Transform3D
	if not _dashboard.visible:
		_instrument_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_center_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_dashboard.global_transform = anchor
	if _instrument_car != target:
		_instrument_car = target
		var info := target.get_info()
		_instruments.configure(info["id"] == "concept_gt", info["redline_rpm"])
		_center_mesh.visible = String(info["id"]).begins_with("kestrel")
		opening = true
	_instrument_time += delta
	if opening or _instrument_time >= 1.0 / 24.0:
		_instrument_time = 0.0
		var telemetry := target.get_telemetry()
		var info := target.get_info()
		var controls := {"automatic": target.is_automatic(), "tcs": target.get_tcs(), "abs": target.get_abs()}
		controls["door_open"] = false
		for door: Dictionary in target.get_door_states():
			if bool(door.get("open", false)) or bool(door.get("missing", false)):
				controls["door_open"] = true
		if is_instance_valid(equipment):
			var state: Dictionary = equipment.state_for(target)
			controls["light_mode"] = state["light_mode"]
			controls["signal"] = state["signal"]
			controls["hazards"] = state["hazards"]
			controls["blink"] = fmod(float(equipment.clock), 0.8) < 0.4
		_instruments.set_vehicle_readings(telemetry, info, controls)
		_instrument_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if _center_mesh.visible:
			_center_display.set_readings(telemetry, info, controls)
			_center_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func cycle() -> String:
	mode = (mode + 1) % MODE_NAMES.size()
	_cockpit_yaw = 0.0
	_cockpit_pitch = 0.0
	_track_pos = Vector3.ZERO
	return MODE_NAMES[mode]


func snap() -> void:
	_chase_ready = false
	_speed_effect = 0.0
	_vel = Vector3.ZERO
	_cockpit_ready = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mode == Mode.CHASE:
				_chase_dist = maxf(3.5, _chase_dist * 0.9)
			elif mode == Mode.ORBIT:
				_dist = maxf(3.0, _dist * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == Mode.CHASE:
				_chase_dist = minf(11.0, _chase_dist * 1.1)
			elif mode == Mode.ORBIT:
				_dist = minf(30.0, _dist * 1.1)
	elif event is InputEventMouseMotion and (_dragging or mode == Mode.ORBIT and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		if mode == Mode.COCKPIT:
			_cockpit_yaw = clampf(_cockpit_yaw - event.relative.x * 0.004, -1.9, 1.9)
			_cockpit_pitch = clampf(_cockpit_pitch - event.relative.y * 0.003, -0.55, 0.45)
		else:
			_yaw -= event.relative.x * 0.006
			_pitch = clampf(_pitch + event.relative.y * 0.004, -0.2, 1.3)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_dashboard.hide()
		_instrument_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_center_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mirrors.update_views(delta, self, null, false)
		return
	var tgt := target.get_chase_target()
	var basis := target.get_visual_basis()
	var fwd := -basis.z
	var up := basis.y
	var vel := target.get_velocity()
	var speed := vel.length()
	if mode != Mode.COCKPIT:
		_cockpit_ready = false
	if mode != Mode.CHASE:
		_chase_ready = false
	fov = 62.0
	match mode:
		Mode.CHASE:
			var heading := Vector3(fwd.x, 0, fwd.z).normalized()
			var travel := Vector3(vel.x, 0, vel.z).normalized()
			if heading.is_zero_approx():
				heading = travel if not travel.is_zero_approx() else Vector3.FORWARD
			var drift_weight := 0.24 * smoothstep(3.0, 18.0, speed) * smoothstep(-0.1, 0.5, heading.dot(travel))
			heading = heading.lerp(travel, drift_weight).normalized()
			if look_back:
				heading = -heading
			_speed_effect = lerpf(_speed_effect, smoothstep(8.0, 65.0, speed), 1.0 - exp(-delta * 4.0))
			var distance := _chase_dist + 0.55 * _speed_effect
			var desired := -heading.rotated(Vector3.UP, _yaw if _dragging else 0.0) * distance
			desired += Vector3.UP * (1.3 + _chase_dist * 0.10 + 0.12 * _speed_effect)
			var aim := Vector3.UP * 0.28 + heading * 0.65 * _speed_effect
			# Damp the offset around the moving car so steady travel cannot stretch the spring.
			var offset := _chase_offset - desired
			if not _chase_ready or _chase_offset.dot(desired) <= 0.0:
				_chase_offset = desired
				_look_offset = aim
				_vel = Vector3.ZERO
			else:
				const OMEGA := 8.0
				var step := (_vel + offset * OMEGA) * delta
				var decay := exp(-OMEGA * delta)
				_chase_offset = desired + (offset + step) * decay
				_vel = (_vel - step * OMEGA) * decay
			_look_offset = _look_offset.lerp(aim, 1.0 - exp(-delta * 10.0))
			fov = 60.0 + 4.0 * _speed_effect
			global_position = tgt + _chase_offset
			look_at(tgt + _look_offset, Vector3.UP)
			_chase_ready = true
		Mode.ORBIT:
			var off := Vector3(cos(_yaw) * cos(_pitch), sin(_pitch), sin(_yaw) * cos(_pitch)) * _dist
			global_position = tgt + off
			look_at(tgt, Vector3.UP)
		Mode.COCKPIT:
			global_position = target.get_driver_eye()
			var pads := Input.get_connected_joypads()
			if not pads.is_empty() and not _dragging:
				var axis_x := Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X)
				var axis_y := Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y)
				var yaw_target := -axis_x * 1.7 if absf(axis_x) > 0.18 else 0.0
				var pitch_target := -axis_y * 0.45 if absf(axis_y) > 0.18 else 0.0
				_cockpit_yaw = lerpf(_cockpit_yaw, yaw_target, 1.0 - exp(-delta * 10.0))
				_cockpit_pitch = lerpf(_cockpit_pitch, pitch_target, 1.0 - exp(-delta * 10.0))
			var look_dir := (-fwd if look_back else fwd).rotated(up, _cockpit_yaw)
			look_dir = look_dir.rotated(look_dir.cross(up).normalized(), _cockpit_pitch - 0.09)
			var desired_basis := Basis.looking_at(look_dir, up)
			if _cockpit_ready and -global_basis.z.dot(look_dir) > 0.9:
				global_basis = global_basis.orthonormalized().slerp(desired_basis, 1.0 - exp(-delta * 18.0))
			else:
				global_basis = desired_basis
			_cockpit_ready = true
		Mode.HOOD:
			var eye2 := target.get_driver_eye() + fwd * 1.2 + up * 0.05
			global_position = eye2
			look_at(eye2 + fwd * 10.0 - up * 0.4, up)
			fov = 70.0
		Mode.TRACKSIDE:
			if _track_pos == Vector3.ZERO or _track_pos.distance_to(tgt) > 60.0:
				var side := basis.x * 9.0
				_track_pos = tgt + fwd * 35.0 + side + Vector3.UP * 1.5
			global_position = _track_pos
			look_at(tgt, Vector3.UP)
			fov = clampf(30.0 + _track_pos.distance_to(tgt) * 0.5, 25.0, 60.0)
	if shake > 0.001:
		_shake_phase = fmod(_shake_phase + delta * 38.0, TAU * 3.0)
		var strength := shake * (0.012 if mode == Mode.COCKPIT else 0.04)
		h_offset = sin(_shake_phase) * strength
		v_offset = sin(_shake_phase * 4.0 / 3.0) * strength * 0.55
		shake = maxf(0.0, shake - delta * 3.0)
	else:
		h_offset = 0.0
		v_offset = 0.0
	_update_dashboard(delta)
	mirrors.update_views(delta, self, target, mode == Mode.COCKPIT)
