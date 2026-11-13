extends SceneTree
const Profile := preload("res://scripts/player_progress.gd")
var failures := 0
var scene: Node
func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value: failures += 1
func _initialize() -> void:
	call_deferred("run")
func tick() -> void:
	scene._drive_player(0.1)
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	scene.equipment._process(0.0)
	scene.lesson._process(0.0)
func run() -> void:
	var game := root.get_node("Game")
	var profile := Profile.new()
	# A fresh profile every run: on a fast machine the microsecond clock alone repeats between runs
	# and picked up a leftover profile (with a braking record) from an aborted earlier run.
	profile.profile_path = "user://flow_test_%d_%d.json" % [Time.get_ticks_usec(), randi()]
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.profile_path + suffix))
	# The verdict before the teardown: if the engine hangs on quit, the suite runner sees a verdict
	# and dumps the thread stacks instead of waiting out its timeout.
	print("FIRST DRIVE FLOW TEST ", "OK" if failures == 0 else "FAILED")
	game.progress = profile
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.settings["automatic"] = true
	game.settings["tcs"] = true
	game.settings["abs"] = true
	game.start_lesson = true
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	scene = current_scene
	scene.set_process(false)
	scene.equipment.set_process(false)
	scene.lesson.set_process(false)
	scene.world.paused = false
	scene.world.time_scale = 0.0
	scene.player.reset_to(Transform3D(Basis.IDENTITY, Vector3(-200, 0, -195)))
	scene.world.step_blocking(1.0)
	scene.world.sync_visuals()
	scene.lesson.start()
	Input.action_press("throttle")
	for i in 200:
		tick()
		if scene.player.get_speed_kmh() >= 60: break
	Input.action_release("throttle")
	check(scene.lesson.stage == "accelerate", "Real driving advances introduction to braking exercise")
	Input.action_press("brake")
	for i in 100:
		tick()
		if scene.lesson.stage == "service": break
	Input.action_release("brake")
	check(scene.lesson.stage == "service", "Actual braking produces a valid stop result")
	var result: Dictionary = profile.get_best_braking("kestrel_hatch")
	check(not result.is_empty() and float(result.get("distance_m", 0)) > 1, "Gameplay signal saves measured braking distance")
	scene.player.break_group("bonnet_latch")
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	var damaged := int(scene.player.get_telemetry()["broken_beams"])
	var fuel := float(scene.player.get_telemetry()["fuel_l"])
	scene.lesson.notify_interruption("Bergung zum Service")
	check(scene.equipment.recover_to_service(), "Damaged vehicle can be recovered to service")
	check(damaged >= 6 and int(scene.player.get_telemetry()["broken_beams"]) == damaged, "Recovery keeps actual bonnet damage")
	check(scene.lesson.stage == "service", "Recovery preserves earned braking result")
	Input.action_press("handbrake")
	Input.action_press("service_repair")
	for i in 120:
		tick()
		if int(scene.player.get_telemetry()["broken_beams"]) == 0: break
	Input.action_release("service_repair")
	check(int(scene.player.get_telemetry()["broken_beams"]) == 0, "Holding G performs actual timed service repair")
	check(absf(float(scene.player.get_telemetry()["fuel_l"]) - fuel) < 0.02, "Service repair does not refill tank")
	Input.action_press("refuel")
	for i in 60:
		tick()
		if scene.lesson.stage == "complete": break
	Input.action_release("refuel")
	Input.action_release("handbrake")
	check(scene.lesson.stage == "complete", "Actual fuel delivery completes first-drive loop")
	var reloaded := Profile.new()
	reloaded.profile_path = profile.profile_path
	check(reloaded.load_profile() == OK and reloaded.is_completed("first_drive_complete"), "Completed introduction survives profile reload")
	check(not reloaded.get_best_braking("kestrel_hatch").is_empty(), "Braking result survives profile reload")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.profile_path + suffix))
	# Generator-fed audio (rain, vehicle) sometimes hung the engine on quit: the audio thread kept
	# mixing a generator playback during teardown (gdb: spinning in the generator's mix loop while
	# the main thread joins it). Stop every player, 2D and 3D, and give the mixer a few frames to
	# let go of the playbacks before anything is freed.
	var players: Array[Node] = scene.find_children("*", "AudioStreamPlayer", true, false)
	players.append_array(scene.find_children("*", "AudioStreamPlayer3D", true, false))
	for player in players:
		player.stop()
		player.stream = null
	for i in 3: await process_frame
	if scene.audio: scene.audio.free()
	for player in players:
		if is_instance_valid(player): player.free()
	scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
