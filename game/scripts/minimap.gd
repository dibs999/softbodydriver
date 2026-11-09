extends Control
## North-up map. The overview fits the complete road network and lists marked places.

const BACK := Color(0.0, 0.0, 0.0, 0.0)
const ROAD := Color("#d9dee3")
const PIN := Color("#ffc36c")
const TEXT := Color("#edf3f7")
const MUTED := Color("#a8bacc")

class MapDrawing extends Control:
	var paths: Array[PackedVector2Array] = []
	var streets := PackedVector2Array()
	var places: Array[Dictionary] = []
	var cars: Array = []
	var player: SBVehicle
	var destination := Vector2.INF
	var center := Vector2.ZERO
	var span := 200.0
	var path_color := ROAD
	var rotation_rad := 0.0     # heading-up compact view rotates the world around the player

	func world_xform() -> Transform2D:
		var scale_factor := minf(size.x, size.y) / span
		return Transform2D(rotation_rad, size * 0.5) * Transform2D(0.0, Vector2.ONE * scale_factor, 0.0, Vector2.ZERO) * Transform2D(0.0, -center)

	func _draw() -> void:
		if size.x < 24.0 or size.y < 24.0:
			return
		var scale_factor := minf(size.x, size.y) / span
		var xf := world_xform()
		draw_set_transform_matrix(xf)
		if not streets.is_empty():
			draw_multiline(streets, Color(0, 0, 0, 0.45), 7.0 / scale_factor, true)
		for path in paths:
			if path.size() > 2:
				draw_polyline(path, Color(0, 0, 0, 0.45), 7.0 / scale_factor, true)
		if not streets.is_empty():
			draw_multiline(streets, path_color, 2.1 / scale_factor, true)
		for path in paths:
			if path.size() > 2:
				draw_polyline(path, path_color, 2.1 / scale_factor, true)
		draw_set_transform(Vector2.ZERO)
		if destination.is_finite():
			var target := xf * destination
			target = target.clamp(Vector2(12, 12), size - Vector2(12, 12))
			draw_circle(target, 9, Color("ff8a2b"), false, 3, true)
			draw_line(target - Vector2(4, 0), target + Vector2(4, 0), Color("ff8a2b"), 2, true)
		for i in places.size():
			var p: Vector2 = xf * (places[i]["point"] as Vector2)
			if not Rect2(Vector2(10, 10), size - Vector2(20, 20)).has_point(p):
				continue
			draw_circle(p, 7.0, PIN, true, -1.0, true)
			var label := str(i + 1)
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(font, p + Vector2(-width * 0.5, 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#1a1a1a"))
		for car in cars:
			if not is_instance_valid(car) or car == player:
				continue
			var pos: Vector3 = car.get_position_ws()
			draw_circle(xf * Vector2(pos.x, pos.z), 3.0, Color("#c9d3dc"), true, -1.0, true)
		if is_instance_valid(player):
			var pos := player.get_position_ws()
			var facing := player.get_forward()
			var tip := xf.basis_xform(Vector2(facing.x, facing.z)).normalized()
			if tip.is_zero_approx():
				tip = Vector2.UP
			var side := tip.orthogonal()
			var p := xf * Vector2(pos.x, pos.z)
			draw_circle(p, 9.0, Color(0, 0, 0, 0.55), true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([p + tip * 8.5, p - tip * 5.5 + side * 5.0, p - tip * 2.5, p - tip * 5.5 - side * 5.0]), Color("#ff8a2b"))

var player: SBVehicle
var activity: Node3D
var lesson: Node
var cockpit := false
var _map := MapDrawing.new()
var _clip := Control.new()
var _panel := StyleBoxFlat.new()
var _bounds := Rect2()
var _local_span := 280.0
var _elapsed := 0.0
var overview_open := false
var _compact_visible := true
var _title := "Strecke"
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.bg_color = Color(0.0, 0.0, 0.0, 0.52)
	_panel.border_color = Color(1, 1, 1, 0.09)
	_panel.set_border_width_all(1)
	_panel.set_corner_radius_all(6)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_map)
	get_viewport().size_changed.connect(_layout)
	_layout()


func configure(data: Dictionary, cars: Array, title: String) -> void:
	_title = title
	_map.path_color = data.get("map_path_color", ROAD)
	_map.cars = cars
	var paths: Array = data.get("map_paths", [])
	if paths.is_empty():
		var route: PackedVector3Array = data.get("waypoints", PackedVector3Array()).duplicate()
		if not route.is_empty():
			route.append(route[0])
			paths = [route]
	var has_bounds := false
	for path: PackedVector3Array in paths:
		var line := PackedVector2Array()
		for p in path:
			var point := Vector2(p.x, p.z)
			_bounds = _bounds.expand(point) if has_bounds else Rect2(point, Vector2.ZERO)
			has_bounds = true
			line.append(point)
		_map.paths.append(line)
		if line.size() == 2:
			_map.streets.append_array(line)
	for place: Dictionary in data.get("map_places", []):
		var p: Vector3 = place["position"]
		var point := Vector2(p.x, p.z)
		_map.places.append({"name": place["name"], "point": point})
		_bounds = _bounds.expand(point)
	_local_span = clampf(_bounds.size.length() * 0.23, 170.0, 510.0)
	_layout()


func toggle_compact() -> void:
	_compact_visible = not _compact_visible
	visible = overview_open or _compact_visible


func toggle_overview() -> void:
	overview_open = not overview_open
	visible = overview_open or _compact_visible
	_layout()


func _layout() -> void:
	var viewport := get_viewport_rect().size
	if viewport.x < 120.0 or viewport.y < 120.0:
		return
	var legend_width := 0.0
	if overview_open:
		size = Vector2(minf(viewport.x - 34.0, 850.0), minf(viewport.y - 34.0, 540.0))
		position = (viewport - size) * 0.5
		legend_width = minf(size.x * 0.32, 220.0)
	else:
		var side := clampf(minf(viewport.x * 0.16, viewport.y * 0.27), 150.0, 240.0)
		size = Vector2(side, side)
		position = Vector2(viewport.x - size.x - 16.0, 16.0)
	if overview_open:
		_clip.position = Vector2(9, 30)
		_clip.size = size - Vector2(18 + legend_width, 54)
	else:
		_clip.position = Vector2(5, 5)
		_clip.size = size - Vector2(10, 10)
	_map.size = _clip.size
	queue_redraw()
	_update_view()


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(player):
		return
	_elapsed += delta
	if _elapsed >= 1.0 / 20.0:
		_elapsed = 0.0
		_update_view()


func _update_view() -> void:
	_map.player = player
	if activity:
		var target: Vector3 = activity.target()
		_map.destination = Vector2(target.x, target.z)
	if lesson and lesson.visible_in_hud() and lesson.stage == "service":
		var bay: Vector3 = lesson.game.equipment.bay
		_map.destination = Vector2(bay.x, bay.z)
	_map.rotation_rad = 0.0
	if overview_open:
		_map.center = _bounds.get_center()
		var fit := maxf(_bounds.size.x / maxf(1.0, _map.size.x), _bounds.size.y / maxf(1.0, _map.size.y))
		_map.span = maxf(20.0, fit * minf(_map.size.x, _map.size.y) * 1.13)
	elif is_instance_valid(player):
		var p := player.get_position_ws()
		var f := player.get_forward()
		_map.center = Vector2(p.x, p.z)
		_map.span = _local_span
		if Vector2(f.x, f.z).length() > 0.1:
			_heading = lerp_angle(_heading, -PI * 0.5 - Vector2(f.x, f.z).angle(), 0.35)
		_map.rotation_rad = _heading
	_map.queue_redraw()


func _draw() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(_clip.position, _clip.size), Color(0.03, 0.04, 0.05, 0.62))
	var font := ThemeDB.fallback_font
	if not overview_open:
		# North marker on the rim of the heading-up map.
		var north := _map.world_xform().basis_xform(Vector2(0, -1)).normalized()
		var c := _clip.position + _clip.size * 0.5
		var edge := c + north * (minf(_clip.size.x, _clip.size.y) * 0.5 - 11.0)
		draw_circle(edge, 9.0, Color(0, 0, 0, 0.6), true, -1.0, true)
		var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, edge + Vector2(-w * 0.5, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff8a2b"))
		return
	var caption := _title + "  /  Übersicht" if overview_open else _title
	draw_string(font, Vector2(12, 21), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48.0, 15, TEXT)
	draw_string(font, Vector2(_clip.position.x + _clip.size.x - 15, 21), "↑ N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	var hint := "K / Esc  Schließen" if overview_open else "K  Karte    N  Ausblenden"
	draw_string(font, Vector2(12, size.y - 7), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	if overview_open:
		var left := _clip.position.x + _clip.size.x + 13.0
		draw_string(font, Vector2(left, 52), "ORTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
		for i in _map.places.size():
			var y := 83.0 + i * 26.0
			draw_circle(Vector2(left + 7, y - 5), 7.0, PIN, true, -1.0, true)
			draw_string(font, Vector2(left + 4, y - 2), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, BACK)
			draw_string(font, Vector2(left + 20, y), _map.places[i]["name"], HORIZONTAL_ALIGNMENT_LEFT, size.x - left - 26.0, 14, TEXT)
