extends Control
## In-game HUD: analog instrument cluster (tachometer, speedometer, gear, warning lamps, fuel and
## coolant gauges), engine panel, tyre panel, damage map, info bar and help overlay.

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
var _rpm_disp := 0.0
var _kmh_disp := 0.0
var font: Font

const C_PANEL := Color(0.03, 0.035, 0.045, 0.72)
const C_EDGE := Color(1, 1, 1, 0.10)
const C_DIM := Color(1, 1, 1, 0.55)
const C_TEXT := Color(0.95, 0.96, 0.98)
const C_ACCENT := Color(1.0, 0.62, 0.15)
const C_RED := Color(1.0, 0.22, 0.15)


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
		_rpm_disp = lerpf(_rpm_disp, float(_t["rpm"]), clampf(delta * 14.0, 0.0, 1.0))
		_kmh_disp = lerpf(_kmh_disp, float(_t["speed_kmh"]), clampf(delta * 10.0, 0.0, 1.0))
	_stats_timer -= delta
	if _stats_timer <= 0.0 and world:
		_stats = world.get_stats()
		_stats_timer = 0.5
	_toast_t = maxf(0.0, _toast_t - delta)
	queue_redraw()


# ------------------------------------------------------------------ drawing helpers
func _w(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _txt(pos: Vector2, s: String, size := 15, col := C_TEXT) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_c(center_x: float, y: float, s: String, size := 15, col := C_TEXT) -> void:
	draw_string(font, Vector2(center_x - _w(s, size) * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_r(right_x: float, y: float, s: String, size := 15, col := C_TEXT) -> void:
	draw_string(font, Vector2(right_x - _w(s, size), y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2, radius := 10.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, r)


func _bar(pos: Vector2, width: float, frac: float, col: Color, label: String, value: String) -> void:
	# Label left and value right on one line, bar below; everything stays inside `width`.
	_txt(pos, label, 13, C_DIM)
	_txt_r(pos.x + width, pos.y, value, 13)
	var r := Rect2(pos + Vector2(0, 6), Vector2(width, 6))
	draw_rect(r, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(r.position, Vector2(width * clampf(frac, 0.0, 1.0), 6)), col)


func _damage_color(d: float) -> Color:
	if d < 0.02:
		return Color(0.25, 0.78, 0.38, 0.9)
	return Color(0.96, 0.84, 0.2, 0.92).lerp(Color(0.96, 0.15, 0.1, 0.95), clampf((d - 0.02) / 0.5, 0.0, 1.0))


func _dial(center: Vector2, radius: float, value: float, max_v: float, major: float, minor: float,
		label_div: float, red_from: float, unit: String) -> void:
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	draw_circle(center, radius + 6, Color(0.0, 0.0, 0.0, 0.55))
	draw_arc(center, radius + 6, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0, true)
	if red_from < max_v:
		var ar := a0 + sweep * red_from / max_v
		draw_arc(center, radius - 5, ar, a0 + sweep, 32, Color(0.9, 0.12, 0.08, 0.85), 8.0, true)
	var steps := int(round(max_v / minor))
	var per_major := int(round(major / minor))
	for i in steps + 1:
		var v := i * minor
		var a := a0 + sweep * v / max_v
		var dir := Vector2(cos(a), sin(a))
		var is_major := i % per_major == 0
		var l := 14.0 if is_major else 7.0
		var col := C_TEXT if v < red_from else Color(1, 0.35, 0.3)
		draw_line(center + dir * (radius - l), center + dir * radius, col, 2.5 if is_major else 1.2, true)
		if is_major:
			var lbl := str(int(round(v / label_div)))
			var p := center + dir * (radius - 30)
			_txt(p + Vector2(-_w(lbl, 15) * 0.5, 6), lbl, 15, col)
	# Needle.
	var av := a0 + sweep * clampf(value / max_v, 0.0, 1.04)
	var nd := Vector2(cos(av), sin(av))
	var side := Vector2(-nd.y, nd.x)
	draw_colored_polygon(PackedVector2Array([center + side * 4.0 - nd * 14.0, center + nd * (radius - 8), center - side * 4.0 - nd * 14.0]), C_ACCENT)
	draw_circle(center, 9, Color(0.12, 0.12, 0.13))
	draw_circle(center, 4, C_ACCENT)
	_txt_c(center.x, center.y + radius * 0.62, unit, 12, C_DIM)


func _lamp(pos: Vector2, label: String, on: bool, col: Color) -> float:
	var w := _w(label, 12) + 14.0
	var r := Rect2(pos, Vector2(w, 20))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.bg_color = col if on else Color(1, 1, 1, 0.05)
	draw_style_box(sb, r)
	_txt(pos + Vector2(7, 15), label, 12, Color(0.05, 0.05, 0.05) if on else Color(1, 1, 1, 0.28))
	return w + 6.0


# ------------------------------------------------------------------ main draw
func _draw() -> void:
	var vs := get_viewport_rect().size
	if _t.is_empty():
		return
	_draw_cluster(vs)
	_draw_engine_panel(vs)
	_draw_damage_panel(vs)
	_draw_tyre_panel(vs)
	_draw_info(vs)
	if _toast_t > 0.0:
		_txt_c(vs.x / 2, vs.y * 0.2, _toast, 24, Color(1, 1, 1, clampf(_toast_t, 0.0, 1.0)))
	if show_help:
		_draw_help(vs)


func _draw_cluster(vs: Vector2) -> void:
	var w := 640.0
	var h := 250.0
	var r := Rect2(Vector2(vs.x * 0.5 - w * 0.5, vs.y - h - 14), Vector2(w, h))
	_panel(r, 18)
	var redline := float(info.get("redline_rpm", 6500.0))
	var max_rpm := ceilf((redline + 1000.0) / 1000.0) * 1000.0
	var tach_c := r.position + Vector2(130, 118)
	var speed_c := r.position + Vector2(w - 130, 118)
	_dial(tach_c, 100, _rpm_disp, max_rpm, 1000, 500, 1000, redline, "x1000 U/min")
	var top_speed := 300.0 if float(info.get("peak_power_kw", 150)) > 250 else 280.0
	_dial(speed_c, 100, _kmh_disp, top_speed, 40 if top_speed < 290 else 50, 10, 1, top_speed + 1, "km/h")
	# Centre: digital speed, gear, gearbox mode.
	var cx := r.position.x + w * 0.5
	_txt_c(cx, r.position.y + 72, "%d" % int(round(_kmh_disp)), 52)
	_txt_c(cx, r.position.y + 92, "km/h", 13, C_DIM)
	var g := int(_t["gear"])
	var gear_s := "N" if g == 0 else ("R" if g < 0 else str(g))
	var auto_mode := vehicle.is_automatic() if vehicle else true
	_txt_c(cx, r.position.y + 150, gear_s, 48, C_ACCENT)
	var mode_s := "LEERLAUF"
	if g > 0:
		mode_s = "AUTOMATIK" if auto_mode else "MANUELL"
	elif g < 0:
		mode_s = "RÜCKWÄRTS"
	_txt_c(cx, r.position.y + 168, mode_s, 11, C_DIM)
	# Mini gauges: fuel + coolant.
	var fuel := float(_t["fuel_l"])
	var cap := float(info.get("fuel_capacity", 50.0))
	var ct := float(_t["coolant_temp"])
	var gx := cx - 56
	var gy := r.position.y + 186
	_txt(Vector2(gx, gy), "TANK", 10, C_DIM)
	draw_rect(Rect2(gx, gy + 4, 112, 5), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(gx, gy + 4, 112 * clampf(fuel / cap, 0, 1), 5), Color(0.9, 0.9, 0.9) if fuel > cap * 0.12 else C_RED)
	_txt(Vector2(gx, gy + 22), "TEMP", 10, C_DIM)
	draw_rect(Rect2(gx, gy + 26, 112, 5), Color(1, 1, 1, 0.08))
	var tcol := Color(0.35, 0.65, 1.0) if ct < 70 else (Color(0.3, 0.9, 0.45) if ct < 108 else C_RED)
	draw_rect(Rect2(gx, gy + 26, 112 * clampf((ct - 40.0) / 100.0, 0, 1), 5), tcol)
	# Warning lamps.
	var low_tyre := false
	var any_burst := false
	var tp: Array = _t.get("tire_pressure", [])
	for i in tp.size():
		if _t["wheel_burst"][i] or tp[i] < 22.0:
			low_tyre = true
		any_burst = any_burst or _t["wheel_burst"][i]
	var blink := fmod(Time.get_ticks_msec() * 0.003, 2.0) < 1.2
	var lamps := [
		["MOTOR", bool(_t["seized"]) or float(_t["engine_damage"]) > 0.05 or bool(_t["head_gasket"]), C_ACCENT],
		["ÖL", bool(_t["running"]) and float(_t["oil_pressure"]) < 0.8, C_RED],
		["TEMP", ct > 112.0 and blink, C_RED],
		["KÜHLM.", float(_t["coolant_level"]) < 0.4, C_ACCENT],
		["TANK", fuel < cap * 0.12, C_ACCENT],
		["REIFEN", low_tyre and (blink or not any_burst), C_ACCENT],
		["TCS", bool(_t["tcs_active"]) or (vehicle != null and not vehicle.get_tcs()), C_ACCENT],
		["ABS", bool(_t["abs_active"]) or (vehicle != null and not vehicle.get_abs()), C_ACCENT],
		["P", Input.get_action_strength("handbrake") > 0.1, C_RED],
	]
	var total := 0.0
	for l in lamps:
		total += _w(l[0], 12) + 20.0
	var lx := cx - (total - 6.0) * 0.5
	var ly := r.end.y - 30
	for l in lamps:
		lx += _lamp(Vector2(lx, ly), l[0], l[1], l[2])
	if not bool(_t["running"]):
		_txt_c(cx, r.position.y + 26, "MOTOR FEST" if bool(_t["seized"]) else "MOTOR AUS", 14, C_RED)


func _draw_engine_panel(vs: Vector2) -> void:
	var w := 300.0
	var r := Rect2(Vector2(16, vs.y - 236), Vector2(w, 222))
	_panel(r)
	var x := r.position.x + 14
	var iw := w - 28
	var title := "%s · %s" % [info.get("engine", ""), info.get("layout", "")]
	_txt(Vector2(x, r.position.y + 24), title, 15)
	var ct := float(_t["coolant_temp"])
	var ccol := Color(0.35, 0.65, 1.0) if ct < 70 else (Color(0.3, 0.9, 0.45) if ct < 108 else C_RED)
	_bar(Vector2(x, r.position.y + 52), iw, (ct - 40.0) / 100.0, ccol, "Kühlwasser", "%.0f °C" % ct)
	_bar(Vector2(x, r.position.y + 82), iw, float(_t["coolant_level"]), Color(0.3, 0.6, 1.0), "Kühlmittelstand", "%.0f %%" % (float(_t["coolant_level"]) * 100.0))
	var ot := float(_t["oil_temp"])
	var half := (iw - 14) * 0.5
	_bar(Vector2(x, r.position.y + 112), half, (ot - 40.0) / 110.0, Color(0.92, 0.7, 0.2) if ot < 135 else C_RED, "Öltemp.", "%.0f °C" % ot)
	var op := float(_t["oil_pressure"])
	_bar(Vector2(x + half + 14, r.position.y + 112), half, op / 5.0, Color(0.92, 0.7, 0.2) if op > 0.8 or not bool(_t["running"]) else C_RED, "Öldruck", "%.1f bar" % op)
	var fuel := float(_t["fuel_l"])
	var cap := float(info.get("fuel_capacity", 50.0))
	_bar(Vector2(x, r.position.y + 142), iw, fuel / cap, Color(0.88, 0.88, 0.88) if fuel > cap * 0.12 else C_ACCENT, "Kraftstoff", "%.1f l · %.1f l/h" % [fuel, float(_t["fuel_rate"])])
	var status := String(_t["status"])
	if status != "":
		var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		var s := "⚠ " + status
		var size := 17 if _w(s, 17) < iw else 14
		_txt(Vector2(x, r.position.y + 180), s, size, Color(1.0, 0.3, 0.2, blink))
	elif bool(_t["fan_on"]):
		_txt(Vector2(x, r.position.y + 180), "Kühlerlüfter läuft", 14, Color(0.6, 0.85, 1.0))
	_txt(Vector2(x, r.position.y + 205), "%.0f kW" % float(_t["power_kw"]), 13, C_DIM)
	_txt_r(r.end.x - 14, r.position.y + 205, "Thermostat %d %%" % int(float(_t["thermostat"]) * 100.0), 13, C_DIM)


func _draw_damage_panel(vs: Vector2) -> void:
	var r := Rect2(Vector2(vs.x - 196, 16), Vector2(180, 262))
	_panel(r)
	_txt(r.position + Vector2(14, 24), "Schäden", 15)
	var zones: Array = _t["zones"]
	var cx := r.position.x + 90
	var top := r.position.y + 42
	var w := 64.0
	var h := 150.0
	var body := Rect2(cx - w / 2, top, w, h)
	draw_rect(Rect2(body.position, Vector2(w, 32)), _damage_color(zones[0]))
	draw_rect(Rect2(body.position + Vector2(0, h - 32), Vector2(w, 32)), _damage_color(zones[1]))
	draw_rect(Rect2(body.position + Vector2(0, 34), Vector2(12, h - 68)), _damage_color(zones[2]))
	draw_rect(Rect2(body.position + Vector2(w - 12, 34), Vector2(12, h - 68)), _damage_color(zones[3]))
	draw_rect(Rect2(body.position + Vector2(14, 34), Vector2(w - 28, h - 68)), _damage_color(zones[4]) * Color(1, 1, 1, 0.65))
	var bursts: Array = _t["wheel_burst"]
	var susp: Array = _t["suspension_damage"]
	var tyre_pos := [Vector2(cx - w / 2 - 16, top + 22), Vector2(cx + w / 2 + 4, top + 22), Vector2(cx - w / 2 - 16, top + h - 54), Vector2(cx + w / 2 + 4, top + h - 54)]
	for i in mini(4, bursts.size()):
		draw_rect(Rect2(tyre_pos[i], Vector2(12, 32)), Color(0.15, 0.15, 0.15, 0.95) if not bursts[i] else C_RED)
		if i < susp.size() and susp[i] > 0.02:
			draw_rect(Rect2(tyre_pos[i], Vector2(12, 32)), _damage_color(susp[i]), false, 2.0)
	var y := top + h + 24
	var rad := float(_t["radiator_damage"])
	_txt(Vector2(r.position.x + 14, y), "Kühler", 13, C_DIM)
	_txt_r(r.end.x - 14, y, "%d %%" % int(rad * 100.0), 13, _damage_color(rad))
	_txt(Vector2(r.position.x + 14, y + 20), "Motor", 13, C_DIM)
	if bool(_t["seized"]):
		_txt_r(r.end.x - 14, y + 20, "FEST", 13, C_RED)
	else:
		var ed := float(_t["engine_damage"])
		_txt_r(r.end.x - 14, y + 20, "%d %%" % int(ed * 100.0), 13, _damage_color(ed))


func _draw_tyre_panel(vs: Vector2) -> void:
	var wear: Array = _t.get("tire_wear", [])
	if wear.size() < 4:
		return
	var temp: Array = _t["tire_temp"]
	var press: Array = _t["tire_pressure"]
	var r := Rect2(Vector2(vs.x - 196, 290), Vector2(180, 170))
	_panel(r)
	_txt(r.position + Vector2(14, 24), "Reifen", 15)
	var names := ["VL", "VR", "HL", "HR"]
	for i in 4:
		var col_x := r.position.x + 14 + (i % 2) * 84
		var row_y := r.position.y + 40 + (i / 2) * 62
		var t := float(temp[i])
		var tc := Color(0.35, 0.65, 1.0) if t < 50 else (Color(0.3, 0.9, 0.45) if t < 105 else (C_ACCENT if t < 135 else C_RED))
		var burst: bool = _t["wheel_burst"][i]
		var box := Rect2(Vector2(col_x, row_y), Vector2(14, 48))
		draw_rect(box, Color(0.1, 0.1, 0.1))
		var remain := clampf(1.0 - float(wear[i]), 0.0, 1.0)
		draw_rect(Rect2(box.position + Vector2(0, 48 * (1.0 - remain)), Vector2(14, 48 * remain)), tc if not burst else C_RED)
		_txt(Vector2(col_x + 20, row_y + 12), names[i], 12, C_DIM)
		if burst:
			_txt(Vector2(col_x + 20, row_y + 28), "PLATT", 12, C_RED)
		else:
			_txt(Vector2(col_x + 20, row_y + 28), "%.1f bar" % (float(press[i]) * 0.0689476), 12)
			_txt(Vector2(col_x + 20, row_y + 44), "%d°C %d%%" % [int(t), int(remain * 100.0)], 11, C_DIM)


func _draw_info(vs: Vector2) -> void:
	var name := String(info.get("name", ""))
	var rtf := float(_stats.get("realtime_factor", 1.0))
	var line2 := "Kamera: %s   ·   %d FPS" % [camera_name, Engine.get_frames_per_second()]
	var line3 := "Physik %d Hz · %d %% Echtzeit · %d Nodes · %d Beams" % [int(_stats.get("physics_hz", 2000)), int(rtf * 100.0), int(_stats.get("nodes", 0)), int(_stats.get("beams", 0))]
	var w := maxf(maxf(_w(name, 18), _w(line2, 13)), _w(line3, 13)) + 28
	_panel(Rect2(Vector2(16, 16), Vector2(w, 82)))
	_txt(Vector2(30, 42), name, 18)
	_txt(Vector2(30, 64), line2, 13, C_DIM)
	var sim_col := C_DIM if rtf > 0.95 * (world.time_scale if world else 1.0) else C_ACCENT
	_txt(Vector2(30, 84), line3, 13, sim_col)
	if world and world.time_scale < 0.99:
		_txt(Vector2(30, 124), "ZEITLUPE ×%.2f" % world.time_scale, 20, Color(0.5, 0.9, 1.0))
	if world and world.paused:
		_txt_c(vs.x / 2, 60, "PHYSIK PAUSIERT", 26, C_ACCENT)


func _draw_help(vs: Vector2) -> void:
	var lines := [
		"W / S  Gas / Bremse (im Stand: Rückwärts)      A / D  Lenken",
		"Leertaste  Handbremse    Q / E  Gang runter / hoch    M  Automatik / Manuell",
		"I  Motor starten    T  Traktionskontrolle    Z  ABS",
		"C  Kamera (rechte Maustaste: umsehen, Mausrad: Zoom)    V  Rückblick",
		"R  Zurücksetzen    Rücktaste  Reparieren    B  Node-Beam-Ansicht",
		"J  Zeitlupe    P  Physik pausieren    Tab  Fahrzeug wechseln    F6  Hindernis",
		"F1  Hilfe ein/aus    Esc  Menü    Gamepad: RT/LT, Stick, A, LB/RB",
	]
	var w := 0.0
	for l in lines:
		w = maxf(w, _w(l, 14))
	w += 32
	var h := lines.size() * 24 + 20
	var r := Rect2(Vector2(vs.x * 0.5 - w * 0.5, 112), Vector2(w, h))
	_panel(r)
	for i in lines.size():
		_txt(r.position + Vector2(16, 30 + i * 24), lines[i], 14, Color(1, 1, 1, 0.85))
