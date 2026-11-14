extends CanvasLayer
## Photo mode (F10): the simulation pauses where it is, the HUD goes away and the free camera
## flies around the scene (right mouse looks, WASD and Q/E move, Shift faster). The mouse wheel
## sets the focal length, ←/→ the focus distance, ↑/↓ the aperture (depth of field), +/− the
## exposure. F12 saves the picture without the help panel to user://screenshots/, H hides the panel.
const CameraRig := preload("res://scripts/camera_rig.gd")
const UITheme := preload("res://scripts/ui_theme.gd")
const MIN_FOV := 12.0
const MAX_FOV := 95.0
const APERTURES := [0.0, 0.3, 0.6, 1.0, 1.6, 2.4]   # DOF blur amount; 0 = everything sharp
var game: Node
var active := false
var fov := 55.0
var focus := 8.0
var aperture := 0
var exposure := 1.0
var last_path := ""
var _panel: PanelContainer
var _label: Label
var _attributes := CameraAttributesPractical.new()
var _old_attributes: CameraAttributes
var _was_paused := false
var _entered_free := false
var _hud_visible := true
var _map_visible := true


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.05, 0.06, 0.78), 6, 12))
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_label)
	add_child(_panel)
	visible = false


func toggle() -> void:
	if active: leave()
	else: enter()


func enter() -> void:
	if active or game == null: return
	active = true
	var cam: Camera3D = game.cam
	_was_paused = game.world.paused
	game.world.paused = true
	_entered_free = cam.mode != CameraRig.Mode.FREE
	if _entered_free:
		cam.toggle_free()
	fov = cam.fov
	cam.free_fov = fov
	_hud_visible = game.hud.visible
	_map_visible = game.minimap.visible
	game.hud.hide()
	game.minimap.hide()
	_old_attributes = cam.attributes
	cam.attributes = _attributes
	_apply()
	visible = true
	_panel.show()


func leave() -> void:
	if not active: return
	active = false
	var cam: Camera3D = game.cam
	cam.attributes = _old_attributes
	cam.free_fov = 62.0
	if _entered_free and cam.mode == CameraRig.Mode.FREE:
		game.hud.camera_name = cam.toggle_free()
	game.hud.visible = _hud_visible
	game.minimap.visible = _map_visible
	game.world.paused = _was_paused
	visible = false


func _apply() -> void:
	var cam: Camera3D = game.cam
	cam.free_fov = fov
	# The compatibility renderer has no depth of field (Godot warns on every change there).
	var dof_available := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var blur: float = APERTURES[aperture] if dof_available else 0.0
	_attributes.dof_blur_far_enabled = blur > 0.0
	_attributes.dof_blur_near_enabled = blur > 0.0
	_attributes.dof_blur_far_distance = focus * 1.15
	_attributes.dof_blur_far_transition = maxf(1.0, focus * 0.8)
	_attributes.dof_blur_near_distance = focus * 0.6
	_attributes.dof_blur_near_transition = maxf(0.3, focus * 0.4)
	_attributes.dof_blur_amount = blur * 0.08
	_attributes.exposure_multiplier = exposure
	# Equivalent focal length on a full-frame sensor for the vertical field of view.
	var mm := 12.0 / tan(deg_to_rad(fov) * 0.5)
	_label.text = "FOTOMODUS   F12 Foto speichern · F10 zurück · H Hilfe aus\nBrennweite %d mm (Mausrad) · Fokus %.1f m (←/→) · Unschärfe %s (↑/↓) · Belichtung %+.1f EV (+/−)\nRechte Maustaste umsehen · WASD/Q/E fliegen · Shift schneller" % [
		roundi(mm), focus, ("nur mit Renderer Qualität/Leistung" if not dof_available else "aus" if blur == 0.0 else "%d/%d" % [aperture, APERTURES.size() - 1]), log(exposure) / log(2.0)]
	if last_path != "":
		_label.text += "\nGespeichert: " + ProjectSettings.globalize_path(last_path)


func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		fov = clampf(fov * (0.92 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.08), MIN_FOV, MAX_FOV)
		_apply()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_F12:
		capture()
	elif key.pressed and not key.echo and key.physical_keycode == KEY_H:
		_panel.visible = not _panel.visible
	elif key.pressed and key.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
		focus = clampf(focus * (1.12 if key.physical_keycode == KEY_RIGHT else 1.0 / 1.12), 0.5, 400.0)
		_apply()
	elif key.pressed and not key.echo and key.physical_keycode in [KEY_UP, KEY_DOWN]:
		aperture = clampi(aperture + (1 if key.physical_keycode == KEY_UP else -1), 0, APERTURES.size() - 1)
		_apply()
	elif key.pressed and key.physical_keycode in [KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		var up := key.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]
		exposure = clampf(exposure * (pow(2.0, 0.25) if up else pow(2.0, -0.25)), 0.25, 4.0)
		_apply()
	elif key.pressed and key.physical_keycode in [KEY_F10, KEY_ESCAPE]:
		leave()
	else:
		# Everything else (gears, lights, reset …) stays with the paused car; WASD/Q/E fly the
		# camera by polling, so the events themselves are not needed.
		pass
	get_viewport().set_input_as_handled()


## Saves the current view without the help panel. Returns the user:// path.
func capture() -> String:
	var panel_was := _panel.visible
	_panel.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_panel.visible = panel_was
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://screenshots/foto_%s.png" % stamp
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = "user://screenshots/foto_%s_%d.png" % [stamp, n]
	if image == null or image.save_png(path) != OK:
		game.hud.toast("Foto konnte nicht gespeichert werden")
		return ""
	last_path = path
	_apply()
	return path
