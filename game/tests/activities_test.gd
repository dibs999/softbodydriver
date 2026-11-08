extends SceneTree
const Activity := preload("res://scripts/driving_activity.gd")
const Surface := preload("res://scripts/road_surface.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	failed = failed or not value

func run() -> void:
	check(Activity.crossed(Vector3(-2, 0.6, 0), Vector3(2, 0.6, 0), Vector3.ZERO, Vector3.RIGHT), "Forward gate crossing")
	check(not Activity.crossed(Vector3(2, 0.6, 0), Vector3(-2, 0.6, 0), Vector3.ZERO, Vector3.RIGHT), "Reverse crossing rejected")
	check(not Activity.crossed(Vector3(-2, 6, 0), Vector3(2, 6, 0), Vector3.ZERO, Vector3.RIGHT), "Overpass cannot collect lower gate")
	check(not Activity.crossed(Vector3(-2, 0.6, 12), Vector3(2, 0.6, 12), Vector3.ZERO, Vector3.RIGHT), "Missed gate rejected")
	check(not Activity.crossed(Vector3(-80, 0.6, 0), Vector3(2, 0.6, 0), Vector3.ZERO, Vector3.RIGHT), "Teleport cannot collect gate")
	check(Activity.drift_rate(50, 30, 7, 0.8) > 0, "Grounded drift scores")
	check(Activity.drift_rate(50, 30, 7, 0) == 0 and Activity.drift_rate(5, 30, 7, 0.8) == 0, "Airborne wheels and stationary burnout do not score")
	var surfaces := Surface.new()
	var data := {"map_paths": [PackedVector3Array([Vector3(-120, 0, 0), Vector3(120, 0, 0)])]}
	surfaces.configure("hill_roads", data)
	check(surfaces.at(Vector3(63, 0, 4)) == "asphalt" and surfaces.at(Vector3(63, 0, 20)) == "grass", "Road index works across chunk boundaries")
	surfaces.configure("desert", data)
	check(surfaces.at(Vector3.ZERO) == "gravel" and surfaces.at(Vector3(0, 0, 30)) == "sand", "Desert separates road and dunes")
	check(Surface.grip("sand") < Surface.grip("asphalt"), "Loose surface reduces grip")
	var game := root.get_node("Game")
	game.settings["traffic"] = false
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var scene = current_scene
	scene.set_process(false)
	scene.world.paused = true
	var activity = scene.activity
	activity.choose()
	activity.start()
	check(activity.active and activity.route.size() > 8, "Time trial has ordered route")
	activity._process(10)
	check(activity.countdown == 3 and activity.elapsed == 0, "Physics pause freezes countdown and timer")
	scene.world.paused = false
	activity._process(0.01)
	check(activity.active, "Queued start reset does not invalidate a run")
	scene.world.paused = true
	scene.world.step_blocking(0.05)
	scene.world.sync_visuals()
	scene.world.paused = false
	activity._process(0.05)
	scene.world.paused = true
	check(activity.active and not activity._arming, "Countdown arms after reset snapshot arrives")
	var e := InputEventAction.new()
	e.action = "repair_vehicle"
	e.pressed = true
	scene._unhandled_input(e)
	check(not activity.active, "Repair invalidates active run")
	activity.start()
	e.action = "reset_vehicle"
	scene._unhandled_input(e)
	check(not activity.active, "Reset invalidates active run")
	activity.start()
	activity.countdown = 0
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	activity._arming = false
	activity._previous = scene.player.get_position_ws() + Vector3(100, 0, 0)
	scene.world.paused = false
	activity._process(0.1)
	scene.world.paused = true
	check(not activity.active and activity.message.contains("versetzt"), "Unexpected relocation invalidates active run")
	quit(1 if failed else 0)
