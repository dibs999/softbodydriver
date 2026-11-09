extends SceneTree
const Weather := preload("res://scripts/world_weather.gd")
const Surface := preload("res://scripts/road_surface.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var environment := Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var sun := DirectionalLight3D.new()
	host.add_child(sun)
	var camera := Camera3D.new()
	host.add_child(camera)
	var surfaces := Surface.new()
	var world := SBWorld.new()
	host.add_child(world)
	world.paused = true
	var weather := Weather.new()
	host.add_child(weather)
	weather.configure(environment, sun, camera, surfaces, world)
	weather.set_process(false)
	weather.set_shelters([{"center": Vector3(10, 2, 0), "half_extents": Vector3(4, 2, 6)},
		{"center": Vector3.ZERO, "half_extents": Vector3(-1, 1, 1)}])
	check(weather.is_sheltered(Vector3(10, 1, 0)) and not weather.is_sheltered(Vector3(10, 5, 0)), "Roof shields volume below it, not rain above")
	check(not weather.is_sheltered(Vector3(15, 1, 0)) and weather._shelters.size() == 1, "Rain remains outside canopy; invalid volumes ignored")
	var game := root.get_node("Game")
	world.material_library = game.make_material_library()
	var car: SBVehicle = game.spawn_vehicle(world, "res://cars/aurora_sedan.car.json", Transform3D.IDENTITY)
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://cars/aurora_sedan.car.json"))
	world.sync_visuals()
	weather.set_vehicle_shelter(car, definition.body)
	check(weather.is_sheltered(car.get_driver_eye()), "Actual driver's eye lies inside dry cabin")
	check(not weather.is_sheltered(car.get_driver_eye() + car.get_up() * 2.0), "Rain above vehicle remains visible")
	check(not weather.is_sheltered(car.get_driver_eye() + car.get_right() * 3.0), "Rain outside side glass remains visible")
	car.relocate_to(Transform3D(Basis(Vector3.UP, 1.3), Vector3(100, 0, -60)))
	weather._update_cabin()
	check(weather.is_sheltered(car.get_driver_eye()), "Cabin shield follows rotated and recovered vehicle")
	weather.set_vehicle_shelter(null, {})
	check(not weather.is_sheltered(car.get_driver_eye()), "Vehicle change clears previous weather shield")
	var day_energy := sun.light_energy
	weather.cycle_time()
	weather.cycle_time()
	check(weather.hour == 0 and sun.light_energy < day_energy * 0.2, "Night reduces sunlight")
	weather.cycle_weather()
	weather.cycle_weather()
	check(weather._rain.emitting, "Rain enabled by weather selection")
	weather._process(30)
	check(weather.wetness == 0, "Physics pause freezes weather accumulation")
	world.paused = false
	weather._process(20)
	check(weather.wetness == 1 and surfaces.effective_grip("asphalt") < Surface.grip("asphalt"), "Rain lowers wheel grip through shared surface state")
	camera.position = Vector3(100, 20, 30)
	weather._process(0)
	check(weather._rain.global_position.distance_to(camera.position + Vector3(0, 9, 0)) < 0.01, "Rain volume follows camera")
	weather.automatic_time = true
	weather._process(30)
	check(is_equal_approx(weather.hour, 1.0), "Automatic day advances one hour per 30 seconds")
	world.time_scale = 0.25
	weather._process(30)
	check(is_equal_approx(weather.hour, 1.25) and weather._rain.speed_scale == 0.25, "Slow motion scales clock and rain consistently")
	world.time_scale = 1
	weather.cycle_weather()
	weather._process(90)
	check(weather.wetness == 0 and not weather._rain.emitting, "Clear weather dries surfaces gradually")
	host.queue_free()
	await process_frame
	quit(1 if failed else 0)
