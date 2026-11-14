extends SceneTree
const Prompts := preload("res://scripts/driver_prompts.gd")
var failures := 0

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func button(index: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(index: JoyButton) -> void:
	button(index)
	button(index, false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state := root.get_node("Game")
	# Gearbox hotkey saves preferences. Give the entire scene a disposable profile.
	var original_path: String = state.settings_config_path
	var profile := "user://gamepad_controls_%s.cfg" % ("%d_%d" % [Time.get_ticks_usec(), randi()])
	state.settings_config_path = profile
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	state.settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var scene = current_scene
	var world: SBWorld = scene.world
	var car: SBVehicle = scene.player
	var equipment = scene.equipment
	world.paused = true
	world.time_scale = 0.0
	scene.set_process(false)
	equipment.set_process(false)
	var mode: int = scene.cam.mode
	tap(JOY_BUTTON_Y)
	check(scene.cam.mode != mode, "Gamepad Y actually changes camera")
	check(Prompts.using_gamepad and Prompts.hint("refuel") == "D-Pad ←", "Last active gamepad selects matching service hints")
	tap(JOY_BUTTON_DPAD_UP)
	check(equipment.state_for(car)["lights"], "D-pad up actually enables headlights")
	equipment._process(0)
	var lamp: SpotLight3D = equipment.state_for(car)["headlights"][0]
	var low_range := lamp.spot_range
	tap(JOY_BUTTON_DPAD_UP)
	equipment._process(0)
	check(equipment.state_for(car)["light_mode"] == 2 and lamp.spot_range > low_range, "Second light press selects longer-range high beam")
	tap(JOY_BUTTON_DPAD_UP)
	equipment._process(0)
	check(not lamp.visible and not equipment.state_for(car)["lights"], "Third light press switches headlights off")
	var automatic := car.is_automatic()
	tap(JOY_BUTTON_DPAD_DOWN)
	check(car.is_automatic() != automatic, "D-pad down changes gearbox mode")
	car.set_automatic(false)
	var old_gear := int(car.get_telemetry()["gear"])
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	world.step_blocking(0.5)
	world.sync_visuals()
	check(int(car.get_telemetry()["gear"]) > old_gear, "Gamepad RB actually shifts manual gearbox upward")
	button(JOY_BUTTON_X)
	check(Input.get_action_strength("clutch") > 0.99, "Gamepad X provides manual clutch input")
	button(JOY_BUTTON_X, false)
	check(Input.get_action_strength("clutch") == 0.0, "Releasing gamepad clutch releases its action")
	# Back held turns the D-pad into the signals: indicators, hazards, looking back. The D-pad's
	# own actions (lights, gearbox, fuel) stay quiet, and the engine keeps running.
	var signals: Dictionary = equipment.state_for(car)
	var lights_before: bool = signals["lights"]
	var gearbox_before := car.is_automatic()
	button(JOY_BUTTON_BACK)
	button(JOY_BUTTON_DPAD_LEFT)
	check(int(signals["signal"]) == -1, "Back + D-pad left sets the left indicator")
	check(not Input.is_action_pressed("refuel"), "The fuel action stays released while the Back layer is held")
	button(JOY_BUTTON_DPAD_LEFT, false)
	tap(JOY_BUTTON_DPAD_RIGHT)
	check(int(signals["signal"]) == 1, "Back + D-pad right switches to the right indicator")
	tap(JOY_BUTTON_DPAD_UP)
	check(signals["hazards"], "Back + D-pad up switches the hazard lights on")
	button(JOY_BUTTON_DPAD_DOWN)
	check(Input.is_action_pressed("look_back"), "Back + D-pad down held looks back")
	button(JOY_BUTTON_DPAD_DOWN, false)
	check(not Input.is_action_pressed("look_back"), "Letting D-pad down go looks forward again")
	button(JOY_BUTTON_BACK, false)
	check(signals["lights"] == lights_before and car.is_automatic() == gearbox_before, "D-pad lights and gearbox did not react under the Back layer")
	check(car.get_telemetry()["running"], "A Back combo does not switch the engine off")
	check(signals["hazards"], "Hazards stay on after the layer is released")
	button(JOY_BUTTON_BACK)
	tap(JOY_BUTTON_DPAD_UP)
	button(JOY_BUTTON_BACK, false)
	check(not signals["hazards"], "Back + D-pad up again switches the hazards off")
	# Rumble follows what the car does: a hit is a jolt on the heavy motor, ABS chatters the light one.
	var rumble = scene.rumble
	var calm: Vector2 = rumble.levels({"speed_kmh": 0.0}, 0.02)
	check(calm.length() < 0.05, "A car at rest does not rumble (%s)" % calm)
	rumble.impact(80.0)
	var hit: Vector2 = rumble.levels({"speed_kmh": 40.0}, 0.02)
	check(hit.y > 0.8, "A hard impact gives a strong jolt (%.2f)" % hit.y)
	for i in 30: rumble.levels({"speed_kmh": 40.0}, 0.02)
	check(rumble.levels({"speed_kmh": 40.0}, 0.02).y < 0.05, "The jolt fades within a second")
	var abs_peak := 0.0
	for i in 10: abs_peak = maxf(abs_peak, rumble.levels({"speed_kmh": 60.0, "abs_active": true}, 0.02).x)
	check(abs_peak > 0.4, "ABS chatters the light motor (%.2f)" % abs_peak)
	tap(JOY_BUTTON_BACK)
	car.set_input(0, 1, 0, 1)
	world.step_blocking(3.0)
	world.sync_visuals()
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	check(not car.get_telemetry()["running"], "Gamepad Back actually stops engine")
	equipment._process(0)
	var before := float(car.get_telemetry()["fuel_l"])
	world.paused = false
	button(JOY_BUTTON_DPAD_LEFT)
	world.step_blocking(1.0)
	world.sync_visuals()
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	equipment._process(0)
	check(float(car.get_telemetry()["fuel_l"]) > before + 0.7, "Holding gamepad fuel control delivers real fuel")
	button(JOY_BUTTON_DPAD_LEFT, false)
	equipment._process(0)
	check(not equipment.refueling, "Releasing gamepad fuel control stops delivery")
	car.puncture_tire(0, 200)
	world.step_blocking(1.0)
	world.sync_visuals()
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	equipment._process(0)
	check(car.get_telemetry()["tire_pressure"][0] < 1, "Repair fixture has actual tire damage")
	button(JOY_BUTTON_DPAD_RIGHT)
	# Hold a little longer than REPAIR_SECONDS (4 s): fixed 2 kHz steps can end a 4.0 s request
	# at 3.9995 s of simulated time, which made this check flaky.
	world.step_blocking(4.2)
	world.sync_visuals()
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	equipment._process(0)
	check(car.get_telemetry()["tire_pressure"][0] > 25, "Holding gamepad repair control completes physical repair")
	button(JOY_BUTTON_DPAD_RIGHT, false)
	var noise := InputEventJoypadMotion.new()
	noise.axis = JOY_AXIS_LEFT_X
	noise.axis_value = 0.05
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(not Prompts.using_gamepad and Prompts.hint("refuel") == "F", "Keyboard use restores keyboard hints")
	Input.parse_input_event(noise)
	Input.flush_buffered_events()
	check(not Prompts.using_gamepad, "Idle analog drift cannot steal keyboard prompts")
	world.paused = true
	state.settings_config_path = original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
	print("GAMEPAD CONTROLS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
