extends SceneTree
const Weather := preload("res://scripts/world_weather.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var world := SBWorld.new()
	world.paused = true
	host.add_child(world)
	world.add_ground_plane(1)
	var car := world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	if car == null or not car.has_method("get_door_states"):
		check(false, "Native door API required for cabin integration test")
		host.queue_free()
		await process_frame
		quit(1)
		return
	world.step_blocking(1.5)
	world.sync_visuals()
	var environment := Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var camera := Camera3D.new()
	host.add_child(camera)
	var sun := DirectionalLight3D.new()
	host.add_child(sun)
	var weather := Weather.new()
	host.add_child(weather)
	weather.configure(environment, sun, camera, null, world)
	weather.set_process(false)
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://cars/kestrel_hatch.car.json"))
	weather.set_vehicle_shelter(car, definition.body)
	camera.position = car.get_driver_eye()
	weather._process(0)
	check(weather.audio._target_occlusion > 0.8, "Closed cabin camera selects muffled rain mix")
	check(not car.call("get_door_states").is_empty() and weather.is_cabin_sheltered(car.get_driver_eye()), "Latched native doors retain dry cabin")
	check(car.call("set_door_open", 0, true), "Stationary reference door opens through real native API")
	world.step_blocking(4)
	world.sync_visuals()
	camera.position = car.get_driver_eye()
	weather._process(0)
	check(weather.audio._target_occlusion == 0, "Open door unmuffles cockpit rain ambience")
	check(not weather.is_cabin_sheltered(car.get_driver_eye()) and not weather._rain_material.get_shader_parameter("cabin_enabled"), "Physically open door disables shader and CPU cabin shield")
	weather.set_shelters([{"center": car.get_driver_eye(), "half_extents": Vector3(5, 3, 5)}])
	check(weather.is_sheltered(car.get_driver_eye()), "Open door does not disable an independent workshop roof")
	car.set_ignition(false)
	check(car.service_repair(), "Service restores actual door geometry")
	world.step_blocking(0.1)
	world.sync_visuals()
	weather._update_cabin()
	check(weather.is_cabin_sheltered(car.get_driver_eye()) and weather._rain_material.get_shader_parameter("cabin_enabled"), "Repaired and latched door restores cabin envelope")
	host.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failed else 0)
