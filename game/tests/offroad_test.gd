extends SceneTree
## Map integration, ground classification and representative driving sections.
const Driver := preload("res://scripts/ai_driver.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func run() -> void:
	var game := root.get_node("Game")
	game.selected_map = "offroad"
	game.selected_car = "res://cars/basalt_suv.car.json"
	game.settings["traffic"] = true
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var scene = current_scene
	scene.set_process(false)
	scene.audio.set_process(false)
	var world: SBWorld = scene.world
	var car: SBVehicle = scene.player
	world.paused = true
	var data: Dictionary = scene.map_data
	check(data["offroad_length_m"] > 3000, "Main field-track circuit exceeds 3 km")
	check(data["map_paths"].size() == 5 and scene.minimap._map.paths.size() == 5, "All five connected trails reach the minimap")
	# No road cars on the trails: the only traffic is one 4x4 working its way round the loop.
	var traffic: Array = scene.vehicles.filter(func(v): return v != scene.player)
	check(traffic.size() == 1 and String(traffic[0].get_info().get("id", "")) == "trailhead_4x4", "Offroad traffic is a single 4x4, no commuter cars")
	var unpaved := true
	for x in range(-650,651,100):
		for z in range(-650,651,100):
			unpaved = unpaved and scene.surfaces.at(Vector3(x,0,z)) in ["grass","gravel"]
	for path: PackedVector3Array in data["map_paths"]:
		for i in range(0,path.size(),8):
			unpaved = unpaved and scene.surfaces.at(path[i]) == "gravel"
	check(unpaved, "Entire map uses unpaved ground and trail grip")
	world.step_blocking(1)
	world.sync_visuals()
	check(Array(car.get_wheel_load()).min() > 0.4, "Spawn rests on four grounded tyres")
	for section: Array in [[0,0],[0,100],[0,200],[0,300],[1,25],[1,80],[2,25],[2,70]]:
		var path: PackedVector3Array = data["map_paths"][section[0]]
		var index: int = section[1]
		var fwd := (path[index+1]-path[index]).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		car.reset_to(Transform3D(Basis(fwd,right.cross(fwd),right),path[index]+Vector3.UP*0.04))
		car.set_input(0,1,0,0)
		car.set_surface_grip(PackedFloat32Array([0.78,0.78,0.78,0.78]))
		world.step_blocking(0.8)
		world.sync_visuals()
		var start := car.get_position_ws()
		var speeds := PackedFloat32Array()
		speeds.resize(path.size())
		speeds.fill(7.0)
		var driver := Driver.new(car,path,speeds)
		for _step in 100:
			driver.update(0.1)
			world.step_blocking(0.1)
			world.sync_visuals()
		var t := car.get_telemetry()
		var travel := car.get_position_ws().distance_to(start)
		print("SECTION ",section," travel ",travel," speed ",t["speed_kmh"]," broken ",t["broken_beams"])
		check(travel > 25 and int(t["broken_beams"]) == 0 and not true in t["wheel_burst"] and car.get_up().y > 0.6, "Trail section remains driveable " + str(section))
	scene.activity.choose()
	scene.activity.start()
	world.step_blocking(0.05)
	world.sync_visuals()
	world.paused = false
	scene.activity._process(0.01)
	world.paused = true
	check(scene.activity.active and not scene.activity._arming and scene.activity.route.size() > 30, "Offroad time trial arms on the field-track loop")
	quit(1 if failed else 0)
