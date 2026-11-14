extends SceneTree
## Photo mode (F10): pauses the simulation, hides HUD and minimap, flies the free camera, and its
## controls change the focal length, depth of field and exposure; F12 writes a PNG; F10 gives
## everything back as it was.
## Needs a window (run under Xvfb): godot -s res://tests/photo_mode_test.gd
const CameraRig := preload("res://scripts/camera_rig.gd")
var failures := 0

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func key(code: Key, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code)
	key(code, false)

func wheel(button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state := root.get_node("Game")
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	state.settings["traffic"] = false
	state.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	for i in 6: await process_frame
	var scene = current_scene
	var photo = scene.photo
	var cam: Camera3D = scene.cam
	var world: SBWorld = scene.world
	var mode_before: int = cam.mode
	check(not world.paused, "Driving runs before photo mode")
	tap(KEY_F10)
	check(photo.active and world.paused, "F10 opens photo mode and pauses the simulation")
	check(not scene.hud.visible and not scene.minimap.visible, "HUD and minimap are hidden")
	check(cam.mode == CameraRig.Mode.FREE, "The free camera takes over")
	var fov: float = photo.fov
	wheel(MOUSE_BUTTON_WHEEL_UP)
	wheel(MOUSE_BUTTON_WHEEL_UP)
	await process_frame
	check(photo.fov < fov - 2.0 and absf(cam.fov - photo.fov) < 0.01, "Mouse wheel zooms in (%.1f -> %.1f deg)" % [fov, cam.fov])
	tap(KEY_UP)
	var attributes := cam.attributes as CameraAttributesPractical
	check(attributes != null and photo.aperture == 1, "Arrow up opens the aperture one step")
	var far: float = attributes.dof_blur_far_distance
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		check(not attributes.dof_blur_far_enabled, "Compatibility renderer: no depth of field is requested")
	else:
		check(attributes.dof_blur_far_enabled and attributes.dof_blur_amount > 0.0, "Arrow up adds depth of field")
	tap(KEY_RIGHT)
	check(attributes.dof_blur_far_distance > far, "Arrow right moves the focus further away")
	tap(KEY_EQUAL)
	check(attributes.exposure_multiplier > 1.0, "Plus brightens the exposure")
	var gear_before := int(scene.player.get_telemetry()["gear"])
	tap(KEY_E)
	check(int(scene.player.get_telemetry()["gear"]) == gear_before, "Driving keys do not reach the car (E did not shift)")
	var path: String = await photo.capture()
	check(path != "" and FileAccess.file_exists(path), "F12 capture writes a PNG (%s)" % path)
	if path != "":
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		check(image != null and image.get_width() > 0, "The saved picture loads")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	tap(KEY_F10)
	check(not photo.active and not world.paused, "F10 again leaves photo mode and resumes")
	check(scene.hud.visible and scene.minimap.visible, "HUD and minimap come back")
	check(cam.mode == mode_before and cam.attributes != attributes, "Camera mode and attributes are restored")
	print("PHOTO MODE TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
