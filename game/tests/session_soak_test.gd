extends SceneTree
## Headless mechanics soak, not a wall-clock/rendering endurance claim.
## Run with isolated XDG_DATA_HOME; defaults to >=30 simulated minutes, finishing its last cycle.
## Worker time_scale=0; step_blocking advances real native physics. Weather receives the same
## explicit simulation intervals with its optional world-clock reference disconnected.
const DT := 0.25
var scene: Node
var initial_sim := 0.0
var started := 0
var failures := 0
var counts := {"cycles": 0, "drives": 0, "doors": 0, "crashes": 0, "recovery": 0, "repair": 0, "refuel": 0}
var target_seconds := 1800.0
var initial_nodes := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> bool:
	if not value:
		failures += 1
		print("SOAK FAIL ", message)
	return value
func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	scene._unhandled_input(event)
func hold(name: String, pressed: bool) -> void:
	if pressed: Input.action_press(name)
	else: Input.action_release(name)
func clear_controls() -> void:
	for name in ["throttle", "brake", "handbrake", "service_repair", "refuel"]: hold(name, false)
func tick() -> bool:
	scene._drive_player(DT)
	var effects: Node = scene.player.get_node("VehicleEffects")
	effects._surface_timer = 0 # Fixed stepping: still exercise real surface->native grip sampling.
	effects._process(DT)
	scene.world.step_blocking(DT)
	scene.world.sync_visuals()
	scene.equipment._process(DT) # Service duration is derived from native sim_time, not delta/time_scale.
	scene.weather._process(DT)
	scene.cam._process(DT)
	if not check(is_instance_valid(scene.player) and scene.player in scene.world.get_vehicles(), "player retained"): return false
	var t: Dictionary = scene.player.get_telemetry()
	var cap := float(scene.player.get_info()["fuel_capacity"])
	if not check(scene.player.get_position_ws().is_finite() and scene.player.get_velocity().is_finite(), "finite physical pose/velocity"): return false
	for field in ["speed_kmh", "rpm", "fuel_l", "coolant_temp"]:
		if not check(is_finite(float(t[field])), "finite telemetry " + field): return false
	return check(float(t["fuel_l"]) >= 0 and float(t["fuel_l"]) <= cap + 0.001, "fuel remains within physical tank")
func ticks(number: int) -> bool:
	for i in number:
		if not tick(): return false
	return true
func run_cycle() -> bool:
	clear_controls()
	if not check(scene.player.relocate_to(scene.map_data["spawns"][0]), "relocate to safe driving start"): return false
	if not ticks(4): return false
	if not scene.player.get_telemetry()["running"]: action("ignition")
	hold("throttle", true)
	var reached := false
	for i in 40:
		if not tick(): return false
		if scene.player.get_speed_kmh() >= 70:
			reached = true
			break
	hold("throttle", false)
	if not check(reached, "car accelerates above70km/h after previous service"): return false
	hold("brake", true)
	for i in 40:
		if not tick(): return false
		if absf(scene.player.get_speed_kmh()) < 1: break
	hold("brake", false)
	if not check(absf(scene.player.get_speed_kmh()) < 1, "service brake stops vehicle"): return false
	counts.drives += 1
	hold("handbrake", true)
	var before_doors := int(scene.player.get_telemetry()["broken_beams"])
	for side in 2:
		if not check(scene.player.set_door_open(side, true), "door opens after driving and braking"): return false
	if not ticks(16): return false
	for door: Dictionary in scene.player.get_door_states():
		if not check(door.attached and float(door.angle_degrees) > 50, "door physically opens on intact hinges"): return false
	for side in 2:
		if not check(scene.player.set_door_open(side, false), "door closure accepted"): return false
	if not ticks(20): return false
	for door: Dictionary in scene.player.get_door_states():
		if not check(door.latched and float(door.angle_degrees) < 3, "door physically closes and relatches after drive"): return false
	if not check(int(scene.player.get_telemetry()["broken_beams"]) == before_doors, "normal door cycle adds no structural damage"): return false
	counts.doors += 1
	hold("handbrake", false)
	# Repeat the same real authored crash-wall approach, not synthetic damage injection.
	var crash_start := Transform3D(Basis.IDENTITY, Vector3(190, 0, -40))
	if not check(scene.player.relocate_to(crash_start), "relocate to crash approach"): return false
	hold("throttle", true)
	if not ticks(28): return false
	hold("throttle", false)
	var broken := int(scene.player.get_telemetry()["broken_beams"])
	if not check(broken > 0, "authored crash wall causes actual beam damage"): return false
	counts.crashes += 1
	if not check(scene.equipment.recover_to_service(), "equipment recovery accepted"): return false
	for i in 40:
		if not tick(): return false
		if scene.equipment.can_refuel(): break
	if not check(scene.equipment.can_refuel(), "recovered damaged vehicle settles for service"): return false
	if not check(int(scene.player.get_telemetry()["broken_beams"]) >= broken, "recovery retains crash damage"): return false
	hold("service_repair", true)
	if not ticks(20): return false
	hold("service_repair", false)
	if not check(int(scene.player.get_telemetry()["broken_beams"]) == 0, "service restores beam structure"): return false
	hold("refuel", true)
	if not ticks(12): return false
	hold("refuel", false)
	if not tick(): return false
	action("headlights")
	action("hazards")
	action("camera_next")
	scene.weather.cycle_weather()
	scene.weather.cycle_time()
	counts.cycles += 1
	return true
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): target_seconds = maxf(1, float(arg.trim_prefix("--minutes=")) * 60)
	var state := root.get_node("Game")
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	state.settings["traffic"] = false
	state.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	scene = current_scene
	scene.set_process(false)
	scene.world.paused = true
	scene.world.time_scale = 0
	scene.world.sync_visuals()
	scene.world.paused = false
	scene.weather._world = null
	scene.weather.automatic_time = true
	scene.audio.set_process(false)
	scene.world.set_process(false)
	scene.weather.set_process(false)
	scene.weather.audio.set_process(false)
	scene.equipment.set_process(false)
	scene.cam.set_process(false)
	scene.player.get_node("VehicleEffects").set_process(false)
	for player in scene.find_children("*", "AudioStreamPlayer", true, false): player.stop()
	for player in scene.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	scene.lesson.skip()
	scene.equipment.service_completed.connect(func(kind: String):
		if counts.has(kind): counts[kind] += 1)
	initial_sim = float(scene.world.get_stats()["sim_time"])
	started = Time.get_ticks_msec()
	initial_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	while float(scene.world.get_stats()["sim_time"]) - initial_sim < target_seconds:
		if not run_cycle(): break
		# Let queued scene-node deletions complete without advancing the disabled worker.
		await process_frame
		await process_frame
		if not check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) < initial_nodes + 250, "scene node count remains bounded"): break
		print("SOAK PROGRESS simulated=%.2fs wall=%.2fs counts=%s" % [float(scene.world.get_stats()["sim_time"]) - initial_sim, (Time.get_ticks_msec() - started) / 1000.0, counts])
	var elapsed := float(scene.world.get_stats()["sim_time"]) - initial_sim
	check(elapsed >= target_seconds, "requested simulated duration completed")
	check(counts.repair == counts.cycles and counts.refuel >= counts.cycles, "every complete cycle includes repair and fuel delivery")
	print("SOAK RESULT simulated=%.3fs wall=%.3fs failures=%d counts=%s" % [elapsed, (Time.get_ticks_msec() - started) / 1000.0, failures, counts])
	clear_controls()
	scene.world.paused = true
	for player in scene.find_children("*", "AudioStreamPlayer", true, false): player.stop()
	for player in scene.find_children("*", "AudioStreamPlayer3D", true, false): player.stop()
	await create_timer(0.1).timeout
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
