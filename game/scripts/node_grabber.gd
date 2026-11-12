extends Node3D
## Node grabber (as in BeamNG): Ctrl + left mouse button picks the nearest node of any car under
## the cursor and pulls it towards the cursor with a capped spring (up to 9 kN, enough to lift a corner) while the button is held.
## The mouse wheel moves the grab point nearer or further. A line from the node to the cursor shows
## the pull, yellow when slack, red when the spring is at its limit.

var game: Node3D
var _car: SBVehicle
var _node := -1
var _distance := 0.0
var _line: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()

const PICK_RADIUS := 0.35   # m from the cursor ray
const FULL_PULL := 1.8      # m stretch at which the spring reaches its cap (9 kN / 5 kN/m)


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	_line.material_override = _material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func grabbing() -> bool:
	return _node >= 0 and is_instance_valid(_car)


func _input(event: InputEvent) -> void:
	if not game or not game.get("cam"):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.ctrl_pressed:
				if grab_at(mb.position):
					get_viewport().set_input_as_handled()
			elif not mb.pressed and grabbing():
				release()
				get_viewport().set_input_as_handled()
		elif grabbing() and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_distance = clampf(_distance * (0.92 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.08), 1.0, 60.0)
			get_viewport().set_input_as_handled()


## Picks the node under the screen position; returns false when no car is there.
func grab_at(screen: Vector2) -> bool:
	var cam: Camera3D = game.cam
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var best_car: SBVehicle = null
	var best_node := -1
	var best_along := INF
	for v: SBVehicle in game.vehicles:
		if not is_instance_valid(v):
			continue
		var n := v.pick_node(origin, dir, PICK_RADIUS)
		if n < 0:
			continue
		var along := (v.get_node_position(n) - origin).dot(dir)
		if along < best_along:
			best_along = along
			best_car = v
			best_node = n
	if best_car == null:
		return false
	_car = best_car
	_node = best_node
	_distance = best_along
	return true


func release() -> void:
	if is_instance_valid(_car):
		_car.release_grab()
	_car = null
	_node = -1
	_mesh.clear_surfaces()


func _process(_delta: float) -> void:
	if not grabbing():
		if _node >= 0:
			release()
		return
	var cam: Camera3D = game.cam
	var screen := get_viewport().get_mouse_position()
	var target := cam.project_ray_origin(screen) + cam.project_ray_normal(screen) * _distance
	_car.set_grab(_node, target)
	var p := _car.get_node_position(_node)
	var strain := clampf(p.distance_to(target) / FULL_PULL, 0.0, 1.0)
	var colour := Color(1.0, 0.85, 0.2).lerp(Color(1.0, 0.2, 0.15), strain)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(p)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(target)
	_mesh.surface_end()
