extends SceneTree
const Lesson := preload("res://scripts/driving_lesson.gd")
var failed := false
var milestones: Array[String] = []
var results: Array = []
var lesson: Node
var now := 0.0
var point := Vector3.ZERO
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func sample(speed: float, brake := 0.0, running := true, broken := 0, dt := 0.1) -> void:
	now += dt
	point.x += speed / 3.6 * dt
	lesson._observe(now, point, {"speed_kmh": speed, "brake": brake, "throttle": 0.0, "running": running, "broken_beams": broken})
func arm() -> void:
	lesson.stage = "accelerate"
	lesson._clock = -1
	sample(60)
	sample(59, 1)
func run() -> void:
	lesson = Lesson.new()
	root.add_child(lesson)
	lesson.set_process(false)
	lesson.milestone_completed.connect(func(id: String): milestones.append(id))
	lesson.brake_result.connect(func(distance: float, speed: float): results.append([distance, speed]))
	lesson.stage = "ignition"
	sample(0, 0, false)
	sample(0, 0, false)
	check(lesson.stage == "ignition", "Stopped engine cannot complete ignition stage")
	sample(0)
	check(lesson.stage == "drive", "Actual running telemetry advances ignition")
	for i in 40: sample(20)
	check(lesson.stage == "accelerate" and milestones.has("first_drive"), "Driving twenty metres unlocks braking guide")
	lesson._clock = -1
	sample(40)
	sample(38, 1)
	check(lesson.stage == "accelerate", "Sub-50 km/h braking is not measured")
	arm()
	check(lesson.stage == "brake" and lesson.brake_start_speed == 60, "Braking starts at actual pre-brake speed")
	for i in 20: sample(maxf(0, 56 - i * 3), 1)
	for i in 3: sample(0, 1)
	check(lesson.stage == "service" and results.size() == 1 and results[0][0] > 10, "Measured stop emits distance result and service goal")
	var earned_distance: float = lesson.brake_distance
	lesson.notify_interruption("Bergung")
	check(lesson.stage == "service" and lesson.brake_distance == earned_distance, "Recovery preserves already completed brake result")
	lesson._on_service_completed("repair")
	check(lesson.stage == "service", "Repair does not count as refueling")
	lesson._on_service_completed("refuel")
	check(lesson.stage == "complete" and milestones.has("first_drive_complete"), "Delivered fuel completes guided loop")
	arm()
	point += Vector3(40, 0, 0)
	sample(30, 1)
	check(lesson.stage == "accelerate" and lesson.brake_distance == 0, "Teleport invalidates brake attempt")
	arm()
	lesson.notify_interruption("Reparatur")
	check(lesson.stage == "accelerate" and lesson.brake_start_speed == 0, "Explicit repair/reset invalidates attempt even without damage")
	arm()
	sample(0, 1)
	check(lesson.stage == "accelerate", "Instant reset stop cannot pass as braking")
	arm()
	sample(50, 1, true, 2)
	check(lesson.stage == "accelerate", "Collision with broken beams invalidates attempt")
	arm()
	sample(45, 1, true, 0, 1.0)
	check(lesson.stage == "accelerate", "Large snapshot gap invalidates distance")
	lesson.skip()
	check(lesson.stage == "skipped" and not lesson.visible_in_hud(), "Skipping hides optional lesson")
	# Actual scene integration: use a temporary XDG_DATA_HOME when invoking this runner.
	var state := root.get_node("Game")
	state.settings["traffic"] = false
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var scene = current_scene
	scene.set_process(false)
	scene.world.paused = true
	lesson.configure(scene)
	lesson.start()
	lesson._process(5)
	check(lesson.stage == "ignition" and lesson._clock == -1, "Actual paused world cannot advance lesson")
	scene.activity.mode = 1
	check(not lesson.visible_in_hud(), "Lesson hides while another activity is selected")
	scene.activity.mode = 0
	scene.world.paused = false
	lesson._process(0.1)
	scene.world.step_blocking(0.05)
	scene.world.sync_visuals()
	lesson._process(0.1)
	check(lesson.stage == "drive", "Actual vehicle running snapshot advances lesson")
	scene.world.paused = true
	scene.audio.set_process(false)
	for audio_player in current_scene.find_children("*", "AudioStreamPlayer", true, false):
		audio_player.stop()
	for audio_player in current_scene.find_children("*", "AudioStreamPlayer3D", true, false):
		audio_player.stop()
	await create_timer(0.1).timeout
	lesson.queue_free()
	current_scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
