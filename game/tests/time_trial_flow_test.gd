extends SceneTree
const Activity := preload("res://scripts/driving_activity.gd")
const Progress := preload("res://scripts/player_progress.gd")
var failures := 0
var results: Array[Dictionary] = []
func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var state := root.get_node("Game")
	var original_progress = state.progress
	state.progress = Progress.new()
	state.progress.profile_path = "user://trial_profile_%s.json" % Time.get_ticks_usec()
	state.settings["traffic"] = false
	state.settings["automatic"] = true
	state.settings["tcs"] = true
	state.settings["abs"] = true
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var game = current_scene
	game.set_process(false)
	var world: SBWorld = game.world
	world.time_scale = 0
	world.paused = false
	var car: SBVehicle = game.player
	var activity = game.activity
	activity.set_process(false)
	var fail_record_save := "--record-save-failure" in OS.get_cmdline_user_args()
	activity.records_path = ("user://missing_trial_%s/records.cfg" if fail_record_save else "user://trial_%s.cfg") % Time.get_ticks_usec()
	activity._records = ConfigFile.new()
	activity.completed.connect(func(result: Dictionary): results.append(result))
	activity.choose()
	activity.start()
	check(activity.active and activity.route.size() > 8, "Actual oval has ordered checkpoint route")
	world.paused = true
	activity._process(30)
	check(activity.elapsed == 0 and activity.countdown == 3, "Paused wall time cannot advance countdown")
	world.paused = false
	var route: PackedVector3Array = game.map_data["waypoints"]
	var index := 0
	var distance_driven := 0.0
	var old_position := Vector3.INF
	var max_speed := 0.0
	var last_gate := 1
	for frame in 4500:
		if not activity.active: break
		if activity.countdown <= 0 and not activity._arming:
			var position := car.get_position_ws()
			# Pure pursuit through the map's real painted oval. Only native inputs
			# are used after the normal activity start reset; gates are never forced.
			for search in 5:
				var a := route[index]
				var b := route[(index + 1) % route.size()]
				if (position - a).dot(b - a) > (b - a).length_squared() * 0.5:
					index = (index + 1) % route.size()
				else: break
			var target := route[(index + 2) % route.size()]
			var toward := target - position
			toward.y = 0
			var angle := atan2(toward.dot(-car.get_right()), toward.dot(car.get_forward()))
			var steer := clampf(atan2(2 * 2.6 * sin(angle), toward.length()) / 0.55, -1, 1)
			var speed := car.get_speed_kmh() / 3.6
			car.set_input(clampf((12.0 - speed) * 0.4, 0, 0.65), clampf((speed - 12.5) * 0.5, 0, 0.7), steer, 0)
		world.step_blocking(0.05)
		world.sync_visuals()
		activity._process(0.05)
		var position := car.get_position_ws()
		if old_position.is_finite(): distance_driven += position.distance_to(old_position)
		old_position = position
		max_speed = maxf(max_speed, car.get_speed_kmh())
		if activity.gate != last_gate:
			print("gate ", activity.gate, "/", activity.route.size() - 1, " at ", activity.elapsed)
			last_gate = activity.gate
		if frame == 150:
			var elapsed_before: float = activity.elapsed
			world.paused = true
			activity._process(100)
			check(activity.elapsed == elapsed_before, "Pause freezes running race clock")
			world.paused = false
	check(results.size() == 1 and not activity.active, "Native driving crosses every gate and emits exactly one completion")
	check(distance_driven > 1000 and max_speed > 30, "Completed lap covers full kilometre at actual driving speed")
	if results.size() == 1:
		var result := results[0]
		check(result["mode"] == 1 and result["map_id"] == "proving_grounds" and result["checkpoints"] == activity.route.size() - 1, "Completion carries route, mode and all checkpoints")
		check(result["improved"] and result["result"] > 60, "First physical lap reports real timed personal best")
		var profile := Progress.new()
		profile.profile_path = state.progress.profile_path
		check(profile.load_profile() == OK and profile.is_completed("time_trial_complete"), "Actual completion signal persists milestone across profile reload")
		if fail_record_save:
			check(not result["record_saved"] and result["record_save_error"] != OK and activity.best == 0 and activity.message.contains("Speichern fehlgeschlagen"), "Real finish reports write failure without claiming a persisted best")
		else:
			var records := ConfigFile.new()
			check(result["record_saved"] and records.load(activity.records_path) == OK and absf(float(records.get_value("proving_grounds:" + result["car_id"], "1", 0)) - result["result"]) < 0.001, "Fresh profile reload reads exact recorded lap")
	else:
		print("FAILED lap position=", car.get_position_ws(), " gate=", activity.gate, " speed=", car.get_speed_kmh(), " message=", activity.message, " damage=", car.get_telemetry().get("broken_beams"))
	activity.start()
	check(activity.last_result.is_empty(), "Retry clears previous completion")
	var repair := InputEventAction.new()
	repair.action = "repair_vehicle"
	repair.pressed = true
	game._unhandled_input(repair)
	check(results.size() <= 1 and activity.last_result.is_empty(), "Cancellation cannot manufacture a race result")
	activity.start()
	world.step_blocking(0.1)
	world.sync_visuals()
	activity._process(0.1)
	car.relocate_to(Transform3D(Basis.IDENTITY, car.get_position_ws() + Vector3(60, 0, 0)))
	activity._process(0.01)
	check(not activity.active and activity.message.contains("versetzt") and results.size() <= 1, "Actual native relocation invalidates run without completion")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.records_path))
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state.progress.profile_path + suffix))
	state.progress = original_progress
	if game.audio: game.audio.free()
	game.queue_free()
	await process_frame
	print("TIME TRIAL FLOW TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
