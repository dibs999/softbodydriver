extends Control
## In-game HUD: speedometer / tachometer, gear, driver aids, engine & cooling gauges, warnings,
## a top-down damage map (body zones, tyres, radiator, engine) and the help overlay.

var vehicle: SBVehicle
var info: Dictionary = {}
var world: SBWorld
var camera_name := "Verfolger"
var show_help := true
var _toast := ""
var _toast_t := 0.0
var _t: Dictionary = {}
var _stats: Dictionary = {}
var _stats_timer := 0.0
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func toast(msg: String) -> void:
	_toast = msg
	_toast_t = 2.5


func _process(delta: float) -> void:
	if vehicle and is_instance_valid(vehicle):
		_t = vehicle.get_telemetry()
	_stats_timer -= delta
	if _stats_timer <= 0.0 and world:
		_stats = world.get_stats()
		_stats_timer = 0.5
	_toast_t = maxf(0.0, _toast_t - delta)
	queue_redraw()


func _txt(pos: Vector2, s: String, size := 16, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, size, col)


func _panel(r: Rect2) -> void:
	draw_rect(r, Color(0.02, 0.03, 0.04, 0.62))
	draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)


func _bar(pos: Vector2, size: Vector2, frac: float, col: Color, label: String, value: String) -> void:
	draw_rect(Rect2(pos, size), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(pos, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), col)
	_txt(pos + Vector2(0, -4), label, 13, Color(1, 1, 1, 0.7))
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_txt(pos + Vector2(size.x - w, -4), value, 13, Color.WHITE)


func _damage_color(d: float) -> Color:
	if d < 0.02:
		return Color(0.25, 0.8, 0.35, 0.85)
	return Color(0.95, 0.85, 0.2, 0.9).lerp(Color(0.95, 0.15, 0.1, 0.95), clampf((d - 0.02) / 0.5, 0.0, 1.0))


func _draw() -> void:
	var vs := get_viewport_rect().size
	if _t.is_empty():
		return
	# ------------------------------------------------------------- speed / rpm (bottom right)
	var base := Vector2(vs.x - 330, vs.y - 170)
	_panel(Rect2(base, Vector2(310, 150)))
	var kmh := float(_t["speed_kmh"])
	_txt(base + Vector2(20, 78), "%d" % int(round(kmh)), 64)
	_txt(base + Vector2(150, 78), "km/h", 18, Color(1, 1, 1, 0.7))
	var g := int(_t["gear"])
	var gear_s := "N" if g == 0 else ("R" if g < 0 else str(g))
	var auto_mode := vehicle.is_automatic() if vehicle else true
	_txt(base + Vector2(232, 78), gear_s, 58, Color(1, 0.85, 0.3))
	_txt(base + Vector2(238, 100), "AUTO" if auto_mode else "MAN", 12, Color(1, 1, 1, 0.6))
	var redline := float(info.get("redline_rpm", 6500.0))
	var rpm := float(_t["rpm"])
	var rpm_frac := rpm / (redline * 1.08)
	var bar_pos := base + Vector2(20, 110)
	var bar_w := 270.0
	draw_rect(Rect2(bar_pos, Vector2(bar_w, 14)), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(bar_pos + Vector2(bar_w * redline / (redline * 1.08), 0), Vector2(bar_w * (1.0 - 1.0 / 1.08), 14)), Color(0.8, 0.1, 0.1, 0.45))
	var rc := Color(0.35, 0.8, 1.0) if rpm < redline * 0.9 else Color(1.0, 0.3, 0.2)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * clampf(rpm_frac, 0.0, 1.0), 14)), rc)
	_txt(bar_pos + Vector2(0, 32), "%d U/min" % int(rpm), 13, Color(1, 1, 1, 0.75))
	var lamp_x := base.x + 150
	for lamp in [["TCS", bool(_t["tcs_active"]), vehicle.get_tcs() if vehicle else true], ["ABS", bool(_t["abs_active"]), vehicle.get_abs() if vehicle else true]]:
		var col := Color(1, 0.7, 0.1) if lamp[1] else (Color(1, 1, 1, 0.35) if lamp[2] else Color(0.9, 0.2, 0.2, 0.8))
		_txt(Vector2(lamp_x, bar_pos.y + 32), lamp[0] + ("" if lamp[2] else " AUS"), 13, col)
		lamp_x += 70

	# ------------------------------------------------------------- engine & fluids (bottom left)
	var eb := Vector2(20, vs.y - 230)
	_panel(Rect2(eb, Vector2(300, 210)))
	_txt(eb + Vector2(14, 24), "%s · %s" % [info.get("engine", ""), info.get("layout", "")], 15, Color(1, 1, 1, 0.85))
	var ct := float(_t["coolant_temp"])
	var ccol := Color(0.3, 0.7, 1.0) if ct < 70 else (Color(0.3, 0.9, 0.4) if ct < 108 else Color(1.0, 0.25, 0.15))
	_bar(eb + Vector2(14, 56), Vector2(272, 8), (ct - 40.0) / 100.0, ccol, "Kühlwasser", "%.0f °C" % ct)
	_bar(eb + Vector2(14, 86), Vector2(272, 8), float(_t["coolant_level"]), Color(0.3, 0.6, 1.0), "Kühlmittelstand", "%.0f %%" % (float(_t["coolant_level"]) * 100.0))
	var ot := float(_t["oil_temp"])
	_bar(eb + Vector2(14, 116), Vector2(124, 8), (ot - 40.0) / 110.0, Color(0.9, 0.7, 0.2) if ot < 135 else Color(1, 0.2, 0.1), "Öltemp.", "%.0f °C" % ot)
	var op := float(_t["oil_pressure"])
	_bar(eb + Vector2(162, 116), Vector2(124, 8), op / 5.0, Color(0.9, 0.7, 0.2) if op > 0.8 or not bool(_t["running"]) else Color(1, 0.2, 0.1), "Öldruck", "%.1f bar" % op)
	var fuel := float(_t["fuel_l"])
	var cap := float(info.get("fuel_capacity", 50.0))
	_bar(eb + Vector2(14, 146), Vector2(272, 8), fuel / cap, Color(0.85, 0.85, 0.85) if fuel > cap * 0.12 else Color(1, 0.6, 0.1), "Kraftstoff", "%.1f l  (%.1f l/h)" % [fuel, float(_t["fuel_rate"])])
	var status := String(_t["status"])
	if status != "":
		var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		_txt(eb + Vector2(14, 184), "⚠ " + status, 18, Color(1.0, 0.3, 0.2, blink))
	elif bool(_t["fan_on"]):
		_txt(eb + Vector2(14, 184), "Lüfter an", 14, Color(0.6, 0.85, 1.0))
	_txt(eb + Vector2(14, 202), "%.0f kW" % float(_t["power_kw"]), 13, Color(1, 1, 1, 0.6))

	# ------------------------------------------------------------- damage map (top right)
	var db := Vector2(vs.x - 190, 20)
	_panel(Rect2(db, Vector2(170, 270)))
	_txt(db + Vector2(12, 22), "Schäden", 15, Color(1, 1, 1, 0.85))
	var zones: Array = _t["zones"]
	var cx := db.x + 85
	var top := db.y + 45
	var w := 70.0
	var h := 170.0
	# Body zones: front, rear, left, right, roof (centre).
	draw_rect(Rect2(cx - w / 2, top, w, 34), _damage_color(zones[0]))
	draw_rect(Rect2(cx - w / 2, top + h - 34, w, 34), _damage_color(zones[1]))
	draw_rect(Rect2(cx - w / 2, top + 36, 14, h - 72), _damage_color(zones[2]))
	draw_rect(Rect2(cx + w / 2 - 14, top + 36, 14, h - 72), _damage_color(zones[3]))
	draw_rect(Rect2(cx - w / 2 + 16, top + 36, w - 32, h - 72), _damage_color(zones[4]) * Color(1, 1, 1, 0.6))
	var bursts: Array = _t["wheel_burst"]
	var susp: Array = _t["suspension_damage"]
	var tyre_pos := [Vector2(cx - w / 2 - 16, top + 26), Vector2(cx + w / 2 + 4, top + 26), Vector2(cx - w / 2 - 16, top + h - 58), Vector2(cx + w / 2 + 4, top + h - 58)]
	for i in mini(4, bursts.size()):
		var tc := Color(0.15, 0.15, 0.15, 0.95) if not bursts[i] else Color(0.95, 0.1, 0.1)
		draw_rect(Rect2(tyre_pos[i], Vector2(12, 32)), tc)
		if i < susp.size() and susp[i] > 0.02:
			draw_rect(Rect2(tyre_pos[i], Vector2(12, 32)), _damage_color(susp[i]), false, 2.0)
	_txt(Vector2(db.x + 12, top + h + 22), "Kühler %3.0f %%" % (float(_t["radiator_damage"]) * 100.0), 13, _damage_color(float(_t["radiator_damage"])))
	if bool(_t["seized"]):
		_txt(Vector2(db.x + 12, top + h + 40), "Motor  FEST", 13, Color(1, 0.2, 0.1))
	else:
		_txt(Vector2(db.x + 12, top + h + 40), "Motor  %3.0f %%" % (float(_t["engine_damage"]) * 100.0), 13, _damage_color(float(_t["engine_damage"])))

	# ------------------------------------------------------------- top-left info
	_panel(Rect2(Vector2(20, 20), Vector2(340, 88)))
	_txt(Vector2(34, 44), String(info.get("name", "")), 18)
	var rtf := float(_stats.get("realtime_factor", 1.0))
	_txt(Vector2(34, 66), "Kamera: %s   ·   %d FPS" % [camera_name, Engine.get_frames_per_second()], 13, Color(1, 1, 1, 0.7))
	var sim_col := Color(1, 1, 1, 0.7) if rtf > 0.95 * (world.time_scale if world else 1.0) else Color(1, 0.6, 0.2)
	_txt(Vector2(34, 86), "Physik: %d Hz · %.0f%% Echtzeit · %d Nodes · %d Beams" % [int(_stats.get("physics_hz", 2000)), rtf * 100.0, int(_stats.get("nodes", 0)), int(_stats.get("beams", 0))], 13, sim_col)
	if world and world.time_scale < 0.99:
		_txt(Vector2(34, 128), "ZEITLUPE x%.2f" % world.time_scale, 20, Color(0.5, 0.9, 1.0))
	if world and world.paused:
		_txt(Vector2(vs.x / 2 - 80, 60), "PHYSIK PAUSIERT", 26, Color(1, 0.8, 0.3))

	if _toast_t > 0.0:
		var a := clampf(_toast_t, 0.0, 1.0)
		_txt(Vector2(vs.x / 2, vs.y * 0.22), _toast, 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 0)

	if show_help:
		var hb := Vector2(vs.x / 2 - 260, vs.y - 250)
		_panel(Rect2(hb, Vector2(520, 230)))
		var lines := [
			"W / S  Gas / Bremse (Rückwärts im Stand)   A / D  Lenken",
			"Leertaste  Handbremse   Q / E  Gang runter / hoch   M  Automatik/Manuell",
			"I  Motor starten   T  Traktionskontrolle   Z  ABS",
			"C  Kamera wechseln (rechte Maustaste: umsehen, Mausrad: Zoom)   V  Rückblick",
			"R  Zurücksetzen   Rücktaste  Reparieren   B  Node-Beam-Ansicht",
			"J  Zeitlupe   P  Physik pausieren   Tab  Fahrzeug wechseln",
			"F6  Hindernis-Auto vor dir abstellen   F1  Hilfe   Esc  Menü",
			"Gamepad: RT/LT Gas/Bremse, linker Stick lenken, A Handbremse, LB/RB schalten",
		]
		for i in lines.size():
			_txt(hb + Vector2(16, 28 + i * 25), lines[i], 14, Color(1, 1, 1, 0.85))
