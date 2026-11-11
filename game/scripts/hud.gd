extends Control
## Driving HUD in the style of a simulation sandbox: small translucent "apps" at the screen edges.
##  * bottom right: round gauge with rev arc, digital speed, gear, fuel/temperature and telltales
##  * bottom left:  top-down damage diagram (body zones, engine, tyres and suspension)
##  * top left:     message stack (notifications fade out, vehicle warnings stay)
##  * top centre:   lesson / activity cards and simulation state
##  * top right:    the minimap (minimap.gd) with the clock and weather below it
## Detailed mechanical telemetry is the F2 overlay, the key list the F1 overlay.
const DriverPrompts := preload("res://scripts/driver_prompts.gd")

var vehicle: SBVehicle
var info: Dictionary = {}
var world: SBWorld
var activity: Node3D
var lesson: Node
var equipment: Node
var weather: Node
var _frame_ms := PackedFloat32Array()
var _p95_ms := 0.0
var _mean_ms := 0.0
var camera_name := "Verfolger"
var cockpit := false
var in_dash_instruments := false
var show_help := false
var show_diagnostics := false
var _t: Dictionary = {}
var _stats: Dictionary = {}
var _stats_timer := 0.0
var _rpm_disp := 0.0
var _kmh_disp := 0.0
var _messages: Array[Dictionary] = []   # {text, time}
var _greeted := false
var font: Font
var bold: Font
var _panel_style: StyleBoxFlat
var _chip_style: StyleBoxFlat

const TEXT := Color("f2f2f2")
const MUTED := Color(1, 1, 1, 0.58)
const DIM := Color(1, 1, 1, 0.16)
const ACCENT := Color("ff8a2b")
const GREEN := Color("4fe08a")
const BLUE := Color("4f8dff")
const AMBER := Color("ffc14d")
const RED := Color("ff5a4f")
const BG := Color(0.0, 0.0, 0.0, 0.52)
const MESSAGE_SECONDS := 4.5
const STATUS := {
	"ENGINE SEIZED": "Motor festgelaufen", "OUT OF FUEL": "Tank leer",
	"DRIVESHAFT BROKEN": "Antriebswelle gebrochen", "HEAD GASKET BLOWN": "Zylinderkopfdichtung defekt",
	"OVERHEATING": "Motor überhitzt", "LOW OIL PRESSURE": "Öldruck zu niedrig",
	"LOW COOLANT": "Zu wenig Kühlmittel", "COOLANT LEAK": "Kühlmittelverlust",
	"OIL LEAK": "Ölverlust", "FUEL LEAK": "Kraftstoffverlust", "ENGINE OFF": "Motor aus · I starten",
	"GEARBOX FAILED": "Getriebe ausgefallen · kein Vortrieb", "CLUTCH FAILED": "Kupplung verschlissen · kein Vortrieb",
	"CLUTCH OVERHEATING": "Kupplung überhitzt · entlasten",
	"ENGINE BLOWN": "Motorschaden · Pleuel durch den Block", "VALVES DAMAGED": "Ventile verbogen · Motor läuft unrund",
	"OVER-REV": "Überdrehzahl · Motor nimmt Schaden",
	"ENGINE FIRE": "Motorbrand · aussteigen!", "FUEL FIRE": "Tankbrand · aussteigen!",
	"ENGINE KNOCKING": "Motor klopft · Pleuellager verschlissen", "OIL STARVATION": "Ölmangel · Pumpe saugt in Kurven Luft", "BURNING OIL": "Motor verbrennt Öl · Kolbenringe verschlissen",
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	var heavy := FontVariation.new()
	heavy.base_font = font
	heavy.variation_embolden = 0.7
	bold = heavy
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = BG
	_panel_style.border_color = Color(1, 1, 1, 0.09)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(6)
	_chip_style = _panel_style.duplicate()
	_chip_style.set_corner_radius_all(4)

func toast(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	for m in _messages:
		if m["text"] == message:
			m["time"] = MESSAGE_SECONDS
			return
	_messages.push_front({"text": message, "time": MESSAGE_SECONDS})
	if _messages.size() > 4:
		_messages.resize(4)

func set_driving_help(on: bool) -> void:
	show_help = on

func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 240: _frame_ms.remove_at(0)
	if is_instance_valid(vehicle):
		_t = vehicle.get_telemetry()
		_rpm_disp = lerpf(_rpm_disp, float(_t["rpm"]), 1.0 - exp(-delta * 16))
		_kmh_disp = lerpf(_kmh_disp, float(_t["speed_kmh"]), 1.0 - exp(-delta * 12))
		if not _greeted:
			_greeted = true
			toast("Start: Pause · Steuerung · Aktivitäten" if DriverPrompts.using_gamepad else "F1 Steuerung  ·  F2 Fahrzeugzustand  ·  Esc Pause")
	_stats_timer -= delta
	if _stats_timer <= 0.0 and world:
		_stats = world.get_stats()
		_stats_timer = 0.5
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		if not sorted.is_empty():
			_p95_ms = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
			_mean_ms = 0.0
			for ms in sorted: _mean_ms += ms / sorted.size()
	for i in range(_messages.size() - 1, -1, -1):
		_messages[i]["time"] -= delta
		if _messages[i]["time"] <= 0.0:
			_messages.remove_at(i)
	queue_redraw()

# ------------------------------------------------------------------------------- primitives
func _text(p: Vector2, value: String, size_px := 14, color := TEXT, f: Font = null) -> void:
	draw_string(f if f else font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _width(value: String, size_px: int, f: Font = null) -> float:
	return (f if f else font).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

func _right(p: Vector2, value: String, size_px := 14, color := TEXT, f: Font = null) -> void:
	_text(p - Vector2(_width(value, size_px, f), 0), value, size_px, color, f)

func _centered(p: Vector2, value: String, size_px := 14, color := TEXT, f: Font = null) -> void:
	_text(p - Vector2(_width(value, size_px, f) * 0.5, 0), value, size_px, color, f)

func _panel(rect: Rect2) -> void:
	draw_style_box(_panel_style, rect)

func _bar(p: Vector2, width: float, fraction: float, color := ACCENT) -> void:
	draw_rect(Rect2(p, Vector2(width, 4)), DIM)
	draw_rect(Rect2(p, Vector2(width * clampf(fraction, 0, 1), 4)), color)

static func damage_color(d: float) -> Color:
	if d < 0.03:
		return Color(1, 1, 1, 0.22)
	if d < 0.35:
		return Color("ffe066").lerp(Color("ffa53d"), d / 0.35)
	return Color("ffa53d").lerp(RED, clampf((d - 0.35) / 0.45, 0.0, 1.0))

# ------------------------------------------------------------------------------- layout
func _draw() -> void:
	if _t.is_empty():
		return
	var canvas := get_viewport_rect().size
	_message_stack(canvas)
	var top := 16.0
	if lesson and lesson.visible_in_hud() and not show_help and not show_diagnostics:
		top = _lesson_card(canvas, top) + 10.0
	if activity and activity.mode > 0 and not show_diagnostics and not show_help:
		top = _activity_card(canvas, top) + 10.0
	if world and (world.paused or world.time_scale < 0.99):
		var label := "SIMULATION PAUSIERT" if world.paused else "ZEITLUPE  ×%.2f" % world.time_scale
		var w := _width(label, 14, bold) + 32
		draw_style_box(_chip_style, Rect2((canvas.x - w) * 0.5, top, w, 30))
		_centered(Vector2(canvas.x * 0.5, top + 20), label, 14, AMBER, bold)
	if is_instance_valid(weather):
		var status: String = weather.get_brief() if weather.has_method("get_brief") else weather.get_status()
		var w := _width(status, 12) + 22
		var y := 264.0
		draw_style_box(_chip_style, Rect2(canvas.x - 16 - w, y, w, 24))
		_right(Vector2(canvas.x - 27, y + 16), status, 12, MUTED)
	if Game.settings.get("career", false):
		var money := "Konto  " + preload("res://scripts/career.gd").money_text(Game.progress.get_money())
		var mw := _width(money, 12) + 22
		draw_style_box(_chip_style, Rect2(canvas.x - 16 - mw, 294.0, mw, 24))
		_right(Vector2(canvas.x - 27, 310.0), money, 12, TEXT)
		var contract: Dictionary = Game.progress.get_contract(Game.selected_map)
		if not contract.is_empty():
			var line := "Auftrag  " + preload("res://scripts/career.gd").contract_text(contract)
			var cw := _width(line, 12) + 22
			draw_style_box(_chip_style, Rect2(canvas.x - 16 - cw, 324.0, cw, 24))
			_right(Vector2(canvas.x - 27, 340.0), line, 12, AMBER)
	if not cockpit or not in_dash_instruments:
		_gauge(Vector2(canvas.x - 152, canvas.y - 146))
	_damage_app(Vector2(16, canvas.y - 276))
	_context_prompt(canvas)
	if show_diagnostics:
		_diagnostics(canvas)
	if show_help:
		_help(canvas)

# ------------------------------------------------------------------------------- messages
func _message_stack(_canvas: Vector2) -> void:
	var entries: Array = []
	for w in _warnings():
		entries.append({"text": w, "color": RED, "alpha": 1.0})
	for m in _messages:
		entries.append({"text": m["text"], "color": ACCENT, "alpha": clampf(m["time"] / 0.5, 0.0, 1.0)})
	var y := 16.0
	for e in entries:
		var text: String = e["text"]
		var a: float = e["alpha"]
		var w := minf(_width(text, 14) + 30.0, 520.0)
		var style := _chip_style.duplicate() as StyleBoxFlat
		style.bg_color.a *= a
		style.border_color.a *= a
		draw_style_box(style, Rect2(16, y, w, 30))
		var stripe: Color = e["color"]
		stripe.a = a
		draw_rect(Rect2(16, y, 3, 30), stripe)
		draw_string(font, Vector2(30, y + 20), text, HORIZONTAL_ALIGNMENT_LEFT, w - 22.0, 14, Color(TEXT, a))
		y += 36.0

func _warnings() -> Array[String]:
	var messages: Array[String] = []
	var status: String = _t.get("status", "")
	if not status.is_empty():
		messages.append("Motor aus · %s starten" % DriverPrompts.hint("ignition") if status == "ENGINE OFF" else STATUS.get(status, status))
	var names := ["vorne links", "vorne rechts", "hinten links", "hinten rechts"]
	var pressure: Array = _t.get("tire_pressure", [])
	for i in mini(4, pressure.size()):
		if pressure[i] < 8.0 or bool(_t["wheel_burst"][i]):
			messages.append("Reifen platt · " + names[i])
		elif pressure[i] < 19.0:
			messages.append("Reifendruck niedrig · " + names[i])
	return messages.slice(0, 3)

# ------------------------------------------------------------------------------- top centre
func _lesson_card(canvas: Vector2, y: float) -> float:
	var w := 540.0
	var p := Vector2((canvas.x - w) * 0.5, y)
	_panel(Rect2(p, Vector2(w, 124)))
	draw_rect(Rect2(p, Vector2(w, 3)), ACCENT)
	_text(p + Vector2(18, 26), "FAHREINFÜHRUNG", 12, ACCENT, bold)
	draw_multiline_string(font, p + Vector2(18, 50), lesson.text, HORIZONTAL_ALIGNMENT_LEFT, w - 36, 15, 2, TEXT)
	draw_string(font, p + Vector2(18, 92), lesson.status, HORIZONTAL_ALIGNMENT_LEFT, w - 36, 12, MUTED)
	_bar(p + Vector2(18, 102), w - 36, lesson.progress)
	_text(p + Vector2(18, 118), "%s · Einführung ausblenden oder neu starten" % DriverPrompts.hint("menu"), 10, MUTED)
	return p.y + 124

func _activity_card(canvas: Vector2, y: float) -> float:
	var w := 420.0
	var p := Vector2((canvas.x - w) * 0.5, y)
	var h := 96.0 if activity.active and activity.mode != 2 else 74.0
	_panel(Rect2(p, Vector2(w, h)))
	draw_rect(Rect2(p, Vector2(w, 3)), ACCENT)
	_text(p + Vector2(16, 25), activity.MODES[activity.mode].to_upper(), 12, ACCENT, bold)
	_text(p + Vector2(16, 48), activity.message, 14)
	var best_label := "Best: %d Pkt." % activity.best if activity.mode == 2 else "Best: %.2f s" % activity.best
	_text(p + Vector2(16, 68), "Start · Aktivitätenmenü" if DriverPrompts.using_gamepad else "F3 Wechseln · F4 " + ("Abbruch" if activity.active else "Start"), 11, MUTED)
	if activity.best > 0: _right(p + Vector2(w - 16, 25), best_label, 12, ACCENT)
	if activity.active and activity.mode != 2:
		_text(p + Vector2(16, 88), activity.navigation_hint(), 13, ACCENT)
	var bottom := p.y + h
	if not activity.active and not activity.last_result.is_empty():
		bottom = _activity_result(canvas, activity.last_result, bottom + 8)
	return bottom

func _activity_result(canvas: Vector2, result: Dictionary, y: float) -> float:
	var w := 420.0
	var p := Vector2((canvas.x - w) * 0.5, y)
	_panel(Rect2(p, Vector2(w, 150)))
	_text(p + Vector2(16, 25), "NEUE BESTLEISTUNG" if result.get("improved", false) else "LAUF ABGESCHLOSSEN", 14, ACCENT, bold)
	var drift := int(result.get("mode", 1)) == 2
	var value := float(result.get("result", 0))
	_text(p + Vector2(16, 58), "%d Punkte" % value if drift else "%.2f Sekunden" % value, 24, TEXT, bold)
	var previous := float(result.get("previous_best", 0))
	if previous > 0:
		var difference := value - previous if drift else previous - value
		var comparison := "%+.0f Punkte zur bisherigen Bestleistung" % difference if drift else "%.2f s %s als die bisherige Bestzeit" % [absf(difference), "schneller" if difference >= 0 else "langsamer"]
		_text(p + Vector2(16, 83), comparison, 12, MUTED)
	else:
		_text(p + Vector2(16, 83), "Erster abgeschlossener Lauf", 12, MUTED)
	_text(p + Vector2(16, 108), "Rekord gespeichert" if result.get("record_saved", false) else "Rekord nicht gespeichert · nur diese Sitzung", 12, MUTED if result.get("record_saved", false) else AMBER)
	_text(p + Vector2(16, 134), "Start → Aktivitäten: erneut fahren" if DriverPrompts.using_gamepad else "F4 Erneut fahren · Esc Aktivitäten / Hauptmenü", 11, TEXT)
	return p.y + 150

func _context_prompt(canvas: Vector2) -> void:
	if not is_instance_valid(equipment) or not equipment.has_method("hud_state"):
		return
	var state: Dictionary = equipment.hud_state()
	var prompt: String = state.get("prompt", "")
	if prompt.is_empty():
		return
	var w := _width(prompt, 15) + 40
	var p := Vector2((canvas.x - w) * 0.5, canvas.y - 74)
	draw_style_box(_chip_style, Rect2(p, Vector2(w, 36)))
	draw_rect(Rect2(p + Vector2(0, 33), Vector2(w, 3)), ACCENT)
	_centered(p + Vector2(w * 0.5, 23), prompt, 15)

# ------------------------------------------------------------------------------- gauge
func _gauge(c: Vector2) -> void:
	const R := 118.0
	draw_circle(c, R, BG, true, -1.0, true)
	draw_arc(c, R, 0, TAU, 96, Color(1, 1, 1, 0.09), 1.5, true)
	var redline := maxf(1000.0, float(info.get("redline_rpm", 6500)))
	var max_rpm := ceilf(redline / 1000.0 + 0.6) * 1000.0
	var a0 := deg_to_rad(150.0)
	var sweep := deg_to_rad(240.0)
	var r1 := R - 13.0
	draw_arc(c, r1, a0, a0 + sweep, 96, Color(1, 1, 1, 0.10), 7, true)
	draw_arc(c, r1, a0 + sweep * redline / max_rpm, a0 + sweep, 24, Color(RED, 0.55), 7, true)
	var fraction := clampf(_rpm_disp / max_rpm, 0.0, 1.0)
	if fraction > 0.002:
		draw_arc(c, r1, a0, a0 + sweep * fraction, 96, RED if _rpm_disp > redline * 0.97 else Color(1, 1, 1, 0.92), 7, true)
	for i in range(0, int(max_rpm / 500.0) + 1):
		var rpm := i * 500.0
		var angle := a0 + sweep * rpm / max_rpm
		var ray := Vector2(cos(angle), sin(angle))
		var major := i % 2 == 0
		draw_line(c + ray * (r1 - (12.0 if major else 7.0)), c + ray * (r1 - 4.0), MUTED if rpm < redline else RED, 2.0 if major else 1.0, true)
		if major:
			_centered(c + ray * (r1 - 25.0) + Vector2(0, 5), str(int(rpm / 1000.0)), 13, MUTED if rpm < redline else RED)
	# Speed, gear and gearbox mode.
	var speed := str(roundi(absf(_kmh_disp)))
	_centered(c + Vector2(0, 22), speed, 50, TEXT, bold)
	_centered(c + Vector2(0, 40), "km/h", 12, MUTED)
	var gear := int(_t["gear"])
	var gear_text := "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	draw_style_box(_chip_style, Rect2(c + Vector2(-20, -66), Vector2(40, 36)))
	_centered(c + Vector2(0, -38), gear_text, 26, ACCENT, bold)
	_text(c + Vector2(24, -40), "A" if vehicle.is_automatic() else "M", 11, MUTED)
	_centered(c + Vector2(0, 56), "U/min ×1000", 9, MUTED)
	# Fuel and coolant arcs in the open bottom of the dial.
	var capacity := maxf(1.0, float(info.get("fuel_capacity", 50.0)))
	var fuel := clampf(float(_t["fuel_l"]) / capacity, 0.0, 1.0)
	var temp := clampf((float(_t["coolant_temp"]) - 50.0) / 80.0, 0.0, 1.0)
	var ra := R - 6.0
	draw_arc(c, ra, deg_to_rad(132), deg_to_rad(100), 20, DIM, 3, true)
	draw_arc(c, ra, deg_to_rad(132), deg_to_rad(132 - 32 * fuel), 20, AMBER if fuel < 0.12 else TEXT, 3, true)
	draw_arc(c, ra, deg_to_rad(48), deg_to_rad(80), 20, DIM, 3, true)
	draw_arc(c, ra, deg_to_rad(48), deg_to_rad(48 + 32 * temp), 20, RED if float(_t["coolant_temp"]) > 112 else TEXT, 3, true)
	_text(c + Vector2(-74, 98), "E", 10, MUTED)
	_text(c + Vector2(-48, 112), "F", 10, MUTED)
	_text(c + Vector2(40, 112), "C", 10, MUTED)
	_text(c + Vector2(66, 98), "H", 10, MUTED)
	_telltales(c + Vector2(0, 76))

func _telltales(center: Vector2) -> void:
	var state: Dictionary = equipment.hud_state() if is_instance_valid(equipment) and equipment.has_method("hud_state") else {}
	var blink: bool = state.get("blink", false)
	var signal_dir: int = state.get("signal", 0)
	var hazards: bool = state.get("hazards", false)
	var light_mode: int = state.get("light_mode", 0)
	var x := center.x - 66.0
	var y := center.y
	# Left indicator.
	var left_on := (signal_dir == -1 or hazards) and blink
	draw_colored_polygon(PackedVector2Array([Vector2(x - 7, y), Vector2(x + 3, y - 7), Vector2(x + 3, y + 7)]), GREEN if left_on else DIM)
	# Low / high beam.
	var lx := x + 26.0
	var beam_color := BLUE if light_mode == 2 else (GREEN if light_mode == 1 else DIM)
	draw_arc(Vector2(lx + 3, y), 6.0, -PI * 0.5, PI * 0.5, 10, beam_color, 2.0, true)
	draw_line(Vector2(lx + 3, y - 6), Vector2(lx + 3, y + 6), beam_color, 2.0)
	for k in 3:
		var yy := y - 4.0 + k * 4.0
		draw_line(Vector2(lx - 7, yy + (0.0 if light_mode == 2 else 1.5)), Vector2(lx - 1, yy), beam_color, 1.6, true)
	# Handbrake.
	var hx := x + 52.0
	var hb := Input.is_action_pressed("handbrake")
	draw_arc(Vector2(hx, y), 7.5, 0, TAU, 16, RED if hb else DIM, 1.6, true)
	_centered(Vector2(hx, y + 4.5), "P", 11, RED if hb else DIM, bold)
	# Traction control and ABS: green-grey when armed, amber while intervening or switched off.
	var tcs_color := AMBER if bool(_t["tcs_active"]) or not vehicle.get_tcs() else DIM
	var abs_color := AMBER if bool(_t["abs_active"]) or not vehicle.get_abs() else DIM
	_centered(Vector2(x + 80, y + 4), "TCS", 10, tcs_color, bold)
	_centered(Vector2(x + 106, y + 4), "ABS", 10, abs_color, bold)
	# Right indicator.
	var rx := x + 132.0
	var right_on := (signal_dir == 1 or hazards) and blink
	draw_colored_polygon(PackedVector2Array([Vector2(rx + 7, y), Vector2(rx - 3, y - 7), Vector2(rx - 3, y + 7)]), GREEN if right_on else DIM)
	# Engine warning and door in a second row.
	var status: String = _t.get("status", "")
	var engine_color := DIM
	if not status.is_empty() and status != "ENGINE OFF": engine_color = RED
	elif status == "ENGINE OFF": engine_color = AMBER
	var ex := center.x - 14.0
	var ey := y + 20.0
	draw_polyline(PackedVector2Array([Vector2(ex - 8, ey + 4), Vector2(ex - 8, ey - 3), Vector2(ex - 4, ey - 3), Vector2(ex - 4, ey - 6),
		Vector2(ex + 3, ey - 6), Vector2(ex + 3, ey - 3), Vector2(ex + 8, ey - 3), Vector2(ex + 8, ey + 4), Vector2(ex - 8, ey + 4)]), engine_color, 1.6, true)
	var door: String = state.get("door", "")
	var dx := center.x + 14.0
	var door_color := RED if door == "missing" else (AMBER if door == "open" else DIM)
	draw_polyline(PackedVector2Array([Vector2(dx - 6, ey + 5), Vector2(dx - 6, ey - 2), Vector2(dx - 1, ey - 6), Vector2(dx + 6, ey - 6),
		Vector2(dx + 6, ey + 5), Vector2(dx - 6, ey + 5)]), door_color, 1.6, true)

# ------------------------------------------------------------------------------- damage
func _damage_app(p: Vector2) -> void:
	var size := Vector2(170, 260)
	_panel(Rect2(p, size))
	draw_string(font, p + Vector2(12, 20), String(info.get("name", "Fahrzeug")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 12, TEXT)
	draw_string(font, p + Vector2(12, 36), camera_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 10, MUTED)
	var zones: Array = _t.get("zones", [0, 0, 0, 0, 0, 0])
	var susp: Array = _t.get("suspension_damage", [0, 0, 0, 0])
	var z := func(i: int) -> float: return float(zones[i]) if i < zones.size() else 0.0
	var body := Rect2(p + Vector2(50, 54), Vector2(70, 182))
	var nose := body.size.y * 0.25
	var tail := body.size.y * 0.18
	var side := 11.0
	var zone_box := func(rect: Rect2, color: Color, radii: Array) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.corner_radius_top_left = radii[0]
		sb.corner_radius_top_right = radii[1]
		sb.corner_radius_bottom_right = radii[2]
		sb.corner_radius_bottom_left = radii[3]
		sb.anti_aliasing = true
		draw_style_box(sb, rect)
	# Underbody frame first, then the panels on top (front of the car points up).
	draw_rect(body.grow(-6), damage_color(z.call(5)) * Color(1, 1, 1, 0.6), false, 2.0)
	zone_box.call(Rect2(body.position, Vector2(body.size.x, nose)), damage_color(z.call(0)), [22, 22, 3, 3])
	zone_box.call(Rect2(body.position + Vector2(0, body.size.y - tail), Vector2(body.size.x, tail)), damage_color(z.call(1)), [3, 3, 14, 14])
	var mid_h := body.size.y - nose - tail - 4
	zone_box.call(Rect2(body.position + Vector2(0, nose + 2), Vector2(side, mid_h)), damage_color(z.call(2)), [3, 3, 3, 3])
	zone_box.call(Rect2(body.position + Vector2(body.size.x - side, nose + 2), Vector2(side, mid_h)), damage_color(z.call(3)), [3, 3, 3, 3])
	# Cabin: windscreen, roof and rear window.
	var cabin := Rect2(body.position + Vector2(side + 4, nose + 8), Vector2(body.size.x - 2 * side - 8, mid_h - 12))
	zone_box.call(cabin, damage_color(z.call(4)), [10, 10, 7, 7])
	draw_line(cabin.position + Vector2(3, 14), cabin.position + Vector2(cabin.size.x - 3, 14), Color(0, 0, 0, 0.45), 2.0, true)
	draw_line(cabin.position + Vector2(3, cabin.size.y - 12), cabin.position + Vector2(cabin.size.x - 3, cabin.size.y - 12), Color(0, 0, 0, 0.45), 2.0, true)
	# Engine inside the nose (mechanical state, not panel damage).
	var engine := clampf(maxf(float(_t.get("engine_damage", 0)), float(_t.get("radiator_damage", 0))), 0.0, 1.0)
	var engine_color := damage_color(engine)
	engine_color.a = maxf(engine_color.a, 0.55)
	draw_rect(Rect2(body.position + Vector2(21, 12), Vector2(body.size.x - 42, nose - 22)), engine_color, false, 1.5)
	# Tyres: pressure loss and suspension damage.
	var pressure: Array = _t.get("tire_pressure", [])
	var burst: Array = _t.get("wheel_burst", [])
	var nominal := maxf(20.0, float(pressure.max()) if not pressure.is_empty() else 30.0)
	var corners := [Vector2(-10, 22), Vector2(body.size.x + 2, 22), Vector2(-10, body.size.y - 58), Vector2(body.size.x + 2, body.size.y - 58)]
	for i in 4:
		var loss := 0.0
		if i < pressure.size():
			loss = 1.0 if (i < burst.size() and bool(burst[i])) or float(pressure[i]) < 8.0 else clampf(1.0 - float(pressure[i]) / nominal, 0.0, 1.0) * 1.6
		var d := maxf(loss, float(susp[i]) if i < susp.size() else 0.0)
		var color := damage_color(d)
		color.a = maxf(color.a, 0.45)
		draw_rect(Rect2(body.position + corners[i], Vector2(8, 36)), color)

# ------------------------------------------------------------------------------- overlays
func _overlay(canvas: Vector2, size: Vector2, title: String, close_hint: String) -> Vector2:
	var p := ((canvas - size) * 0.5).floor()
	var style := _panel_style.duplicate() as StyleBoxFlat
	style.bg_color = Color(0.02, 0.02, 0.025, 0.86)
	draw_style_box(style, Rect2(p, size))
	draw_rect(Rect2(p, Vector2(size.x, 3)), ACCENT)
	_text(p + Vector2(22, 34), title, 18, TEXT, bold)
	_right(p + Vector2(size.x - 22, 32), close_hint, 12, MUTED)
	draw_line(p + Vector2(22, 48), p + Vector2(size.x - 22, 48), Color(1, 1, 1, 0.10))
	return p

func _row(p: Vector2, title: String, value: String, fraction: float, color := ACCENT) -> void:
	_text(p, title, 13, MUTED)
	_right(p + Vector2(242, 0), value, 13, color)
	_bar(p + Vector2(0, 8), 242, fraction, color)

func _diagnostics(canvas: Vector2) -> void:
	var p := _overlay(canvas, Vector2(610, 404), "FAHRZEUGZUSTAND", "F2  Schließen")
	_text(p + Vector2(22, 76), "ANTRIEB & KÜHLUNG", 11, ACCENT, bold)
	_row(p + Vector2(22, 104), "Motor", "%d %% intakt" % roundi(100 * (1 - float(_t["engine_damage"]))), 1 - float(_t["engine_damage"]))
	var cw := float(_t.get("clutch_wear", 0))
	var ct := float(_t.get("clutch_temp", 45))
	_row(p + Vector2(22, 145), "Kupplung", "%d %% · %.0f °C" % [roundi((1 - cw) * 100), ct], 1 - cw, RED if cw > 0.65 or ct > 200 else ACCENT)
	var gd := float(_t.get("gearbox_damage", 0))
	_row(p + Vector2(22, 186), "Getriebe", "%d %% intakt" % roundi((1 - gd) * 100), 1 - gd, RED if gd > 0.5 else ACCENT)
	_row(p + Vector2(22, 227), "Kühlmittel", "%.0f °C · %.0f %%" % [_t["coolant_temp"], 100 * float(_t["coolant_level"])], float(_t["coolant_level"]), RED if float(_t["coolant_temp"]) > 115 else ACCENT)
	_row(p + Vector2(22, 268), "Motoröl", "%.0f °C · %.1f bar" % [_t["oil_temp"], _t["oil_pressure"]], float(_t["oil_level"]))
	_text(p + Vector2(320, 76), "REIFEN  /  DRUCK · TEMPERATUR", 11, ACCENT, bold)
	var names := ["Vorne links", "Vorne rechts", "Hinten links", "Hinten rechts"]
	for i in 4:
		var pressure := float(_t["tire_pressure"][i])
		var wear := float(_t["tire_wear"][i])
		var label := "PLATT" if pressure < 8 or bool(_t["wheel_burst"][i]) else "%.1f bar · %.0f °C" % [pressure * 0.0689476, _t["tire_temp"][i]]
		var rims: Array = _t.get("rim_damage", [])
		if i < rims.size() and float(rims[i]) > 0.08:
			label = "Felge verbogen · " + label
		_row(p + Vector2(320, 104 + i * 41), names[i], label, 1 - wear, RED if pressure < 19 or wear > 0.7 else ACCENT)
	_text(p + Vector2(320, 280), "Balken: verbleibendes Reifenprofil", 11, MUTED)
	_text(p + Vector2(22, 320), "Shift  Kupplung    Q / E  Schalten    M  Getriebemodus", 13, TEXT)
	_text(p + Vector2(22, 342), "Rücktaste  Fahrzeug vollständig reparieren", 13, MUTED)
	_text(p + Vector2(22, 367), "%d FPS · %.1f ms Ø / %.1f ms P95 · %d Zeichenaufrufe" % [Engine.get_frames_per_second(), _mean_ms, _p95_ms, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)], 12, MUTED)
	_text(p + Vector2(22, 387), "Physik %d Hz · %.0f %% Echtzeit · Messfenster bis 240 Bilder" % [_stats.get("physics_hz", 2000), 100 * float(_stats.get("realtime_factor", 1))], 11, MUTED)

func _help(canvas: Vector2) -> void:
	var p := _overlay(canvas, Vector2(640, 470), "STEUERUNG", "F1  Schließen")
	if DriverPrompts.using_gamepad:
		draw_multiline_string(font, p + Vector2(24, 82), DriverPrompts.control_summary(), HORIZONTAL_ALIGNMENT_LEFT, 590, 18, -1, TEXT)
		draw_multiline_string(font, p + Vector2(24, 368), "Start öffnet auch Aktivitäten, Wetter und Bergung.\nTanken und Reparatur: im markierten Servicebereich anhalten,\nMotor ausschalten und D-Pad halten.", HORIZONTAL_ALIGNMENT_LEFT, 590, 15, -1, MUTED)
		return
	var lines := [
		[["W", "S", "A", "D"], "Gas & Bremse / Rückwärts  ·  Lenken"],
		[["Leertaste"], "Handbremse"], [["Shift", "Q", "E", "M"], "Kupplung  ·  Schalten  ·  Automatik / Manuell"],
		[["C", "RMT"], "Kamera wechseln  ·  Umsehen, Mausrad zoomt"],
		[["T", "Z", "I"], "Traktionskontrolle  ·  ABS  ·  Motor starten"],
		[["R", "⌫"], "Zurücksetzen  ·  Reparieren"],
		[["K", "N", "F2"], "Karte  ·  Minikarte  ·  Fahrzeugdiagnose"],
		[["F3", "F4"], "Aktivität wählen  ·  Start / Abbruch"],
		[["J", "P", "Tab", "B"], "Zeitlupe  ·  Physikpause  ·  Fahrzeug  ·  Node-Beam-Ansicht"],
		[["L", ",", ".", "H", "⇧H"], "Licht  ·  Blinker  ·  Warnblinker  ·  Blaulicht"],
		[["X", "O", "⏎"], "Scheibenwischer  ·  Haube entriegeln  ·  Hupe"],
		[["F", "G"], "Tanken / Service halten (Motor aus)"],
		[["U", "⇧U"], "Fahrer- / Beifahrertür im Stand"],
		[["F7", "F8"], "Wetter  ·  Tageszeit (Umschalt+F8 Zeitlauf)"],
	]
	for i in lines.size():
		var y := p.y + 80 + i * 27
		var x := p.x + 24
		for key: String in lines[i][0]:
			var w := maxf(22.0, _width(key, 11, bold) + 12.0)
			draw_style_box(_chip_style, Rect2(x, y - 15, w, 21))
			_centered(Vector2(x + w * 0.5, y), key, 11, ACCENT, bold)
			x += w + 4
		_text(Vector2(p.x + 214, y), lines[i][1], 13, TEXT)
