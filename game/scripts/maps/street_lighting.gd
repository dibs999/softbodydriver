extends Node3D
## Street lamps at night. Every lamp lens glows; only the lamps nearest to the camera carry a real
## (shadowless) spot light from a small pool, so hundreds of lamps cost a fixed number of lights.

const POOL := 28
var positions := PackedVector3Array()   # light source positions (under the lamp heads)
var lenses: Array[MeshInstance3D] = []  # optional glowing parts, shown at night
var _lights: Array[SpotLight3D] = []
var _lens_material: StandardMaterial3D
var _timer := 0.0
var night := 0.0


func setup(lamp_positions: PackedVector3Array, lens_material: StandardMaterial3D) -> void:
	positions = lamp_positions
	_lens_material = lens_material
	for i in mini(POOL, positions.size()):
		var light := SpotLight3D.new()
		light.light_color = Color(1.0, 0.84, 0.62)
		light.spot_range = 20.0
		light.spot_angle = 62.0
		light.spot_attenuation = 0.9
		light.spot_angle_attenuation = 1.6
		light.shadow_enabled = false
		light.light_specular = 0.35
		light.rotation_degrees = Vector3(-90, 0, 0)
		light.visible = false
		add_child(light)
		_lights.append(light)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	var scene := get_tree().current_scene
	var weather: Node = scene.get("weather") if scene else null
	var hour := float(weather.get("hour")) if weather else 13.0
	night = 1.0 - smoothstep(-0.12, 0.25, sin((hour - 6.0) * TAU / 24.0))
	if _lens_material:
		_lens_material.emission_energy_multiplier = lerpf(0.0, 4.0, night)
	var camera := get_viewport().get_camera_3d()
	if night < 0.02 or camera == null:
		for light in _lights:
			light.visible = false
		return
	update_pool(camera.global_position)


## Moves the light pool to the lamps nearest to `focus`.
func update_pool(focus: Vector3) -> void:
	var order: Array = []
	for i in positions.size():
		order.append([positions[i].distance_squared_to(focus), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _lights.size():
		var light := _lights[k]
		if k >= order.size():
			light.visible = false
			continue
		light.position = positions[order[k][1]]
		light.light_energy = 7.0 * night
		light.visible = true
