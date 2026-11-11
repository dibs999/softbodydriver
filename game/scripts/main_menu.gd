extends Node3D
## Main menu: vehicle tiles with rendered thumbnails, live soft-body preview of the selected car,
## vehicle card with the start actions, map tiles and a settings overlay.
const UITheme := preload("res://scripts/ui_theme.gd")
const Career := preload("res://scripts/career.gd")

var world: SBWorld
var preview_car: SBVehicle
var cam: Camera3D
var cam_angle := 1.12
var car_name: Label
var car_info: Label
var car_stats: Array[Label] = []
var map_info: Label
var progress_info: Label
var car_buttons: Array[Button] = []
var car_meta: Array[Label] = []   # detail line of each vehicle tile (price or "im Besitz" in the career)
var map_buttons: Array[Button] = []
var start_button: Button
var _preview_area: Control
var _settings: Control
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	_build_scene()
	_apply_graphics()
	Game.graphics_preset_changed.connect(_apply_graphics)
	_build_ui()
	var idx := 0
	for i in Game.cars.size():
		if Game.cars[i]["path"] == Game.selected_car:
			idx = i
	if Game.cars.size() > 0:
		car_buttons[idx].button_pressed = true
		_on_car_selected(idx)
	for i in Game.MAPS.size():
		if Game.MAPS[i]["id"] == Game.selected_map:
			map_buttons[i].button_pressed = true
			_on_map_selected(i)
	if start_button and not start_button.disabled:
		start_button.grab_focus()


# ------------------------------------------------------------------------------- 3D studio
func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("141619")
	# The floor shader fades into this colour, so no horizon edge is visible.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("9aa3ad")
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The floor fades into the backdrop instead of ending at a visible horizon.
	env.environment = e
	add_child(env)
	_env = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -38, 0)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)
	_sun = sun
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_energy = 0.7
	rim.light_color = Color("ffd9b0")
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	floor_mesh.mesh = plane
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://materials/studio_floor.gdshader")
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.3
	torus.outer_radius = 3.33
	torus.rings = 96
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.01
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(UITheme.ACCENT, 0.55)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	add_child(ring)
	world = SBWorld.new()
	world.material_library = Game.make_material_library()
	add_child(world)
	world.add_ground_plane(1.0)
	cam = Camera3D.new()
	cam.fov = 38
	add_child(cam)


func _apply_graphics() -> void:
	Game.apply_environment_graphics(_env, _sun)


# ------------------------------------------------------------------------------- layout
func _panel(alpha := 0.62) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, alpha), 4, 16))
	return p


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.make()
	ui.add_child(root)

	# Top bar.
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.7), 0, 14))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	bar.add_child(top)
	var mark := ColorRect.new()
	mark.color = UITheme.ACCENT
	mark.custom_minimum_size = Vector2(4, 30)
	top.add_child(mark)
	top.add_child(UITheme.label("SOFTBODY DRIVER", 24, UITheme.TEXT, true))
	var tagline := UITheme.label("Soft-Body-Fahrsimulation", 14, UITheme.MUTED)
	tagline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tagline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tagline)
	for entry in [["Einstellungen", _toggle_settings], ["Quellen & Lizenzen", _show_credits], ["Beenden", func(): Game.quit_cleanly()]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		top.add_child(b)

	# Vehicle tiles on the left.
	var garage := _panel()
	garage.anchor_bottom = 1.0
	garage.offset_left = 20
	garage.offset_top = 80
	garage.offset_right = 20 + 478
	garage.offset_bottom = -20
	root.add_child(garage)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 10)
	garage.add_child(gv)
	var head := HBoxContainer.new()
	gv.add_child(head)
	var title := UITheme.section("Fahrzeug")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.label("%d Fahrzeuge" % Game.cars.size(), 12, UITheme.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	gv.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var car_group := ButtonGroup.new()
	for i in Game.cars.size():
		var c: Dictionary = Game.cars[i]
		var tile := _tile(c["name"], _car_meta_text(c), "res://ui/cars/%s.png" % c["id"], Vector2(212, 119), car_group)
		tile.pressed.connect(_on_car_selected.bind(i))
		grid.add_child(tile)
		car_buttons.append(tile)
		car_meta.append(tile.get_child(0).get_child(2) as Label)

	# Vehicle card and actions on the right.
	var card := _panel(0.66)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -20 - 430
	card.offset_right = -20
	card.offset_top = 80
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	card.add_child(cv)
	car_name = UITheme.label("Fahrzeug auswählen", 26, UITheme.TEXT, true)
	car_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cv.add_child(car_name)
	car_info = UITheme.label("", 13, UITheme.MUTED)
	car_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	car_info.custom_minimum_size.x = 396
	cv.add_child(car_info)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	cv.add_child(stats)
	for caption in ["LEISTUNG", "DREHMOMENT", "MASSE"]:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.05), 4, 8))
		stats.add_child(chip)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		chip.add_child(content)
		content.add_child(UITheme.label(caption, 11, UITheme.MUTED))
		var value := UITheme.label("–", 19, UITheme.TEXT, true)
		content.add_child(value)
		car_stats.append(value)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 14)
	cv.add_child(sep)
	map_info = UITheme.label("", 13, UITheme.MUTED)
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.custom_minimum_size.x = 396
	cv.add_child(map_info)
	start_button = Button.new()
	start_button.text = "Losfahren  →"
	start_button.theme_type_variation = &"PrimaryButton"
	start_button.custom_minimum_size.y = 54
	start_button.disabled = Game.cars.is_empty()
	start_button.pressed.connect(_on_start)
	cv.add_child(start_button)
	var lesson_button := Button.new()
	lesson_button.text = "Fahreinführung wiederholen" if Game.progress.is_completed("first_drive_complete") else "Fahreinführung · Fahren, Bremsen & Service"
	lesson_button.disabled = Game.cars.is_empty()
	lesson_button.pressed.connect(func():
		Game.start_lesson = true
		Game.selected_map = "proving_grounds"
		Game.progress.set_selection(Game.selected_car, Game.selected_map)
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	cv.add_child(lesson_button)
	progress_info = UITheme.label("", 12, UITheme.MUTED)
	progress_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_info.custom_minimum_size.x = 396
	cv.add_child(progress_info)

	# Map tiles along the bottom, between garage and the right edge.
	var maps := _panel()
	maps.anchor_top = 1.0
	maps.anchor_right = 1.0
	maps.anchor_bottom = 1.0
	maps.offset_left = 20 + 478 + 16
	maps.offset_right = -20
	maps.offset_top = -20 - 190
	maps.offset_bottom = -20
	root.add_child(maps)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	maps.add_child(mv)
	mv.add_child(UITheme.section("Karte"))
	var mscroll := ScrollContainer.new()
	mscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mscroll.follow_focus = true
	mv.add_child(mscroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	mscroll.add_child(row)
	var map_group := ButtonGroup.new()
	for i in Game.MAPS.size():
		var m: Dictionary = Game.MAPS[i]
		var tile := _tile(m["name"].split(" · ")[0], "", "res://ui/maps/%s.png" % m["id"], Vector2(150, 84), map_group)
		tile.pressed.connect(_on_map_selected.bind(i))
		row.add_child(tile)
		map_buttons.append(tile)

	# Free space for the 3D preview: between garage and card, above the map strip.
	_preview_area = Control.new()
	_preview_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_area.anchor_right = 1.0
	_preview_area.anchor_bottom = 1.0
	_preview_area.offset_left = 20 + 478
	_preview_area.offset_right = -20 - 430
	_preview_area.offset_top = 80
	_preview_area.offset_bottom = -20 - 190
	root.add_child(_preview_area)
	root.move_child(_preview_area, 0)

	var footer := UITheme.label("W/S Gas & Bremse  ·  A/D Lenken  ·  C Kamera  ·  F1 Hilfe  ·  F3 Aktivitäten", 12, UITheme.MUTED)
	footer.anchor_left = 1.0
	footer.anchor_right = 1.0
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = -20 - 430
	footer.offset_right = -20
	footer.offset_top = -20 - 190 - 26
	footer.offset_bottom = -20 - 190 - 6
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(footer)
	_build_settings(root)


## Selectable tile: thumbnail, name and an optional detail line.
func _tile(caption: String, detail: String, image: String, thumb: Vector2, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(thumb.x + 12, thumb.y + (58 if not detail.is_empty() else 40))
	b.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.04), 4, 6))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.10), 4, 6))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.ACCENT, 0.28), 4, 6, UITheme.ACCENT, 2))
	b.add_theme_stylebox_override("hover_pressed", UITheme.box(Color(UITheme.ACCENT, 0.34), 4, 6, UITheme.ACCENT, 2))
	b.tooltip_text = caption
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	v.position = Vector2(6, 6)
	v.size = Vector2(thumb.x, b.custom_minimum_size.y - 12)
	b.add_child(v)
	var tex := TextureRect.new()
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.custom_minimum_size = thumb
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(image):
		tex.texture = load(image)
	v.add_child(tex)
	var name_label := UITheme.label(caption, 14, UITheme.TEXT, true)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = thumb.x
	v.add_child(name_label)
	if not detail.is_empty():
		var d := UITheme.label(detail, 11, UITheme.MUTED)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		d.custom_minimum_size.x = thumb.x
		v.add_child(d)
	return b


# ------------------------------------------------------------------------------- settings
func _build_settings(root: Control) -> void:
	_settings = Control.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	root.add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.06, 0.97), 4, 18, UITheme.BORDER, 1))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(820, 700)
	panel.position = Vector2(-410, -350)
	_settings.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UITheme.label("EINSTELLUNGEN", 22, UITheme.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "Schließen"
	close.pressed.connect(_toggle_settings)
	head.add_child(close)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var page := func(title: String) -> VBoxContainer:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		scroll.add_child(box)
		return box
	var graphics: VBoxContainer = page.call("Grafik")
	graphics.add_child(Game.make_graphics_options())
	var driving: VBoxContainer = page.call("Fahrhilfen")
	for key in [["tcs", "Traktionskontrolle"], ["abs", "ABS"], ["automatic", "Automatikgetriebe"],
			["steering_assist", "Lenkhilfe (glättet Tastatur und begrenzt Lenkeinschlag bei Tempo)"], ["traffic", "KI-Verkehr"],
			["career", "Karriere: Aktivitäten bringen Geld, Tanken und Reparaturen kosten"]]:
		driving.add_child(Game.make_driving_option(key[0], key[1]))
	driving.add_child(Game.make_driving_help_option())
	var audio: VBoxContainer = page.call("Audio")
	audio.add_child(Game.make_audio_options())


func _toggle_settings() -> void:
	_settings.visible = not _settings.visible
	if not _settings.visible: _refresh_garage()


## Tile detail line: layout and power, and in the career the price or that the car is owned.
func _car_meta_text(c: Dictionary) -> String:
	var meta := "%s · %.0f kW" % [c["layout"], c["power"]]
	if _career_on():
		meta += " · im Besitz" if Career.owns(Game.progress, str(c["id"])) else " · " + Career.money_text(Career.car_price(c))
	elif not (c.get("visual_model", {}) as Dictionary).is_empty():
		meta += " · Detailmodell"
	return meta


func _career_on() -> bool:
	return bool(Game.settings.get("career", false))


## The selected car is drivable unless the career is on and it is not bought yet.
func _selected_owned() -> bool:
	var c: Dictionary = Game.car_info(Game.selected_car)
	return c.is_empty() or not _career_on() or Career.owns(Game.progress, str(c["id"]))


## Tiles, start button and account line after a purchase or a change of the career setting.
func _refresh_garage() -> void:
	for i in mini(map_buttons.size(), Game.MAPS.size()):
		var id: String = Game.MAPS[i]["id"]
		var locked := _career_on() and not Career.map_unlocked(Game.progress, id)
		map_buttons[i].modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
		map_buttons[i].tooltip_text = ("Gesperrt · noch %d Aufträge" % Career.contracts_to_unlock(Game.progress, id)) if locked else Game.MAPS[i]["name"]
	for i in mini(car_meta.size(), Game.cars.size()):
		if car_meta[i]: car_meta[i].text = _car_meta_text(Game.cars[i])
	for i in car_buttons.size():
		if car_buttons[i].button_pressed:
			_on_car_selected(i)
			return
	_update_start_button()


func _update_start_button() -> void:
	if not start_button: return
	var c: Dictionary = Game.car_info(Game.selected_car)
	if _career_on() and not Career.map_unlocked(Game.progress, Game.selected_map):
		var left := Career.contracts_to_unlock(Game.progress, Game.selected_map)
		start_button.text = "Karte gesperrt · noch %d %s" % [left, "Auftrag" if left == 1 else "Aufträge"]
		start_button.disabled = true
		start_button.tooltip_text = "Erledige Aufträge auf den offenen Karten, um diese Karte freizuschalten."
		return
	if _selected_owned():
		start_button.text = "Losfahren  →"
		start_button.disabled = Game.cars.is_empty()
		start_button.tooltip_text = ""
		return
	var price := Career.car_price(c)
	var missing := price - Game.progress.get_money()
	start_button.text = "Kaufen · %s" % Career.money_text(price)
	if missing > 0.0: start_button.text += "  ·  es fehlen %s" % Career.money_text(missing)
	start_button.disabled = missing > 0.0 or Game.progress.read_only
	start_button.tooltip_text = "Kontostand %s" % Career.money_text(Game.progress.get_money())


func _unhandled_input(event: InputEvent) -> void:
	if _settings and _settings.visible and event.is_action_pressed("menu"):
		_settings.visible = false
		_refresh_garage()
		get_viewport().set_input_as_handled()


func _show_credits() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Audio- und Bildquellen"
	dialog.theme = UITheme.make()
	dialog.min_size = Vector2i(640, 440)
	add_child(dialog)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.selection_enabled = true
	text.custom_minimum_size = Vector2(620, 400)
	text.text = FileAccess.get_file_as_string("res://ASSET_CREDITS.md")
	var links := RegEx.new()
	links.compile("\\[([^\\]]+)\\]\\((https://[^)]+)\\)")
	text.text = links.sub(text.text, "[url=$2]$1[/url]", true)
	links.compile("(?m)^#{1,3} (.+)$")
	text.text = links.sub(text.text, "[b]$1[/b]", true)
	text.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	dialog.add_child(text)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(660, 480))


# ------------------------------------------------------------------------------- selection
func _on_car_selected(i: int) -> void:
	var c: Dictionary = Game.cars[i]
	Game.selected_car = c["path"]
	if progress_info:
		var record: Dictionary = Game.progress.get_best_braking(str(c["id"]))
		progress_info.text = "Einführung abgeschlossen" if Game.progress.is_completed("first_drive_complete") else "Einführung optional · Fortschritt wird gespeichert"
		if Game.progress.is_completed("time_trial_complete"):
			progress_info.text += " · Zeitfahren abgeschlossen"
		if not record.is_empty():
			progress_info.text += "\nBremsrekord: %.1f m aus %.0f km/h" % [record["distance_m"], record["start_speed_kmh"]]
		var tally: Array[int] = preload("res://scripts/driving_activity.gd").medal_tally()
		if tally[0] + tally[1] + tally[2] > 0:
			progress_info.text += "\nMedaillen: %d Gold · %d Silber · %d Bronze" % [tally[2], tally[1], tally[0]]
		if Game.settings.get("career", false):
			progress_info.text += "\nKarriere · Kontostand %s" % preload("res://scripts/career.gd").money_text(Game.progress.get_money())
			var contract: Dictionary = Game.progress.get_contract(Game.selected_map)
			if not contract.is_empty():
				progress_info.text += "\nAuftrag auf dieser Karte: " + Career.contract_text(contract)
		if Game.progress.read_only:
			progress_info.text = "Fortschritt kann nicht gespeichert werden. Das vorhandene Profil bleibt erhalten."
	_update_start_button()
	car_name.text = c["name"]
	car_info.text = "%s  ·  %s  ·  %s" % [c["engine"], c["layout"], c["description"]]
	car_stats[0].text = "%.0f kW" % c["power"]
	car_stats[1].text = "%.0f Nm" % c["torque"]
	car_stats[2].text = "%.0f kg" % c["mass"]
	if preview_car:
		world.remove_vehicle(preview_car)
		preview_car = null
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-30)), Vector3.ZERO)
	preview_car = Game.spawn_vehicle(world, c["path"], xf)
	if preview_car:
		preview_car.set_input(0, 1, 0, 1)


func _on_map_selected(i: int) -> void:
	Game.selected_map = Game.MAPS[i]["id"]
	map_info.text = "KARTE: %s\n%s" % [Game.MAPS[i]["name"], Game.MAPS[i]["description"]]
	if _career_on(): _refresh_garage()   # contract line, lock state and start button for this map


func _on_start() -> void:
	if not _selected_owned():
		# Career: the first press buys the car, the next one drives it.
		var c: Dictionary = Game.car_info(Game.selected_car)
		if Game.progress.buy_car(str(c["id"]), Career.car_price(c)):
			_refresh_garage()
		return
	Game.start_lesson = false
	Game.progress.set_selection(Game.selected_car, Game.selected_map)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _process(delta: float) -> void:
	cam_angle += delta * 0.15
	var target := Vector3(0, 0.6, 0)
	if preview_car:
		target = preview_car.get_position_ws()
		target.y = 0.62
	var viewport_size := get_viewport().get_visible_rect().size
	var preview_rect := _preview_area.get_global_rect() if _preview_area else Rect2(Vector2.ZERO, viewport_size)
	var length := float(preview_car.get_info().get("length", 4.4)) if preview_car else 4.4
	var distance := length * 1.8
	if preview_rect.size.x > 0.0 and preview_rect.size.y > 0.0:
		# Keep the car inside the free area: fit by the narrower of width and height.
		var available := minf(preview_rect.size.x / 1.7, preview_rect.size.y)
		distance *= clampf(viewport_size.y * 0.62 / available, 1.0, 2.6)
	cam.position = target + Vector3(cos(cam_angle) * distance, distance * 0.24, sin(cam_angle) * distance)
	cam.look_at(target, Vector3.UP)
	var shift := preview_rect.get_center() - viewport_size * 0.5
	var world_per_pixel := 2.0 * distance * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, viewport_size.y)
	cam.h_offset = -shift.x * world_per_pixel
	cam.v_offset = shift.y * world_per_pixel
