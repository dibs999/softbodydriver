extends Control
## Drawn into the in-dash surface only while the cockpit camera is active.

const RESOLUTION := Vector2i(640, 182)
const INK := Color("#080d14")
const EDGE := Color("#253542")
const WHITE := Color("#eef7ff")
const MUTED := Color("#a2b6c5")
const BLUE := Color("#6cd8ff")
const AMBER := Color("#ffba69")
const RED := Color("#ff6252")
const SWEEP_START := 0.75 * PI
const SWEEP_END := 2.25 * PI

var _digital := false
var _redline := 7000.0
var _rpm_max := 8000.0
var _speed := 0.0
var _rpm := 0.0
var _gear := "N"
var readings: Dictionary = {}

static func warning_for(t: Dictionary, info: Dictionary, controls: Dictionary = {}) -> Dictionary:
	if bool(t.get("rod_broken", false)): return {"text": "MOTORSCHADEN", "urgent": true}
	if bool(t.get("seized", false)): return {"text": "MOTOR FEST", "urgent": true}
	if float(t.get("over_rev", 0)) > 1.1: return {"text": "DREHZAHL", "urgent": true}
	if float(t.get("engine_knock", 0)) > 0.05: return {"text": "MOTOR KLOPFT", "urgent": true}
	if float(t.get("fuel_l", 1)) <= 0.01: return {"text": "TANK LEER", "urgent": true}
	if bool(t.get("running", false)) and float(t.get("oil_pressure", 3.0)) < 0.8: return {"text": "ÖLDRUCK", "urgent": true}
	if float(t.get("coolant_temp", 20)) >= 115 or float(t.get("coolant_level", 1)) < 0.25: return {"text": "KÜHLUNG", "urgent": true}
	if float(t.get("gearbox_damage", 0)) >= 0.8: return {"text": "GETRIEBE", "urgent": true}
	if float(t.get("clutch_wear", 0)) >= 0.8 or float(t.get("clutch_temp", 45)) > 220: return {"text": "KUPPLUNG", "urgent": true}
	for pressure in t.get("tire_pressure", []):
		if float(pressure) < 10: return {"text": "REIFENDRUCK", "urgent": true}
	if bool(controls.get("door_open", false)):
		return {"text": "TÜR OFFEN", "urgent": absf(float(t.get("speed_kmh", 0))) > 2.0}
	if float(t.get("fuel_l", 50)) < float(info.get("fuel_capacity", 50)) * 0.1: return {"text": "TANK RESERVE", "urgent": false}
	if not bool(t.get("running", true)): return {"text": "MOTOR AUS", "urgent": false}
	if not str(t.get("status", "")).is_empty(): return {"text": "SERVICE", "urgent": false}
	return {"text": "", "urgent": false}

func set_vehicle_readings(t: Dictionary, info: Dictionary, controls: Dictionary) -> void:
	var blink := bool(controls.get("blink", false))
	readings = {
		"fuel": float(t.get("fuel_l", 0)), "capacity": maxf(1.0, float(info.get("fuel_capacity", 50))),
		"coolant": float(t.get("coolant_temp", 20)), "warning": warning_for(t, info, controls),
		"left": blink and (bool(controls.get("hazards", false)) or int(controls.get("signal", 0)) == -1),
		"right": blink and (bool(controls.get("hazards", false)) or int(controls.get("signal", 0)) == 1),
		"light_mode": int(controls.get("light_mode", 0)), "automatic": bool(controls.get("automatic", true)),
		"tcs": bool(controls.get("tcs", true)), "abs": bool(controls.get("abs", true)),
	}
	set_readings(float(t.get("speed_kmh", 0)), float(t.get("rpm", 0)), int(t.get("gear", 0)))


func configure(digital: bool, redline: float) -> void:
	_digital = digital
	_redline = redline
	_rpm_max = maxf(1000.0, ceilf(redline / 1000.0) * 1000.0)


func set_readings(speed: float, rpm: float, gear: int) -> void:
	_speed = absf(speed)
	_rpm = rpm
	_gear = "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	queue_redraw()


func _text(value: String, point: Vector2, height: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
	draw_string(font, point - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, height, color)


func _dial(center: Vector2, value: float, limit: float, divisions: int, unit: String, accent: Color, warning: float) -> void:
	draw_circle(center, 77.0, INK, true, -1.0, true)
	draw_arc(center, 76.0, 0.0, TAU, 56, EDGE, 2.0, true)
	draw_arc(center, 68.0, SWEEP_START, SWEEP_END, 48, EDGE, 3.0, true)
	var end_angle := lerpf(SWEEP_START, SWEEP_END, clampf(value / limit, 0.0, 1.0))
	draw_arc(center, 68.0, SWEEP_START, end_angle, 40, accent, 3.0, true)
	if warning < limit:
		draw_arc(center, 68.0, lerpf(SWEEP_START, SWEEP_END, warning / limit), SWEEP_END, 12, RED, 3.0, true)
	for i in divisions * 4 + 1:
		var fraction := float(i) / (divisions * 4)
		var direction := Vector2.from_angle(lerpf(SWEEP_START, SWEEP_END, fraction))
		var major := i % 4 == 0
		var tick_color := RED if fraction * limit >= warning else (WHITE if major else MUTED)
		draw_line(center + direction * (57.0 if major else 61.0), center + direction * 65.0, tick_color, 2.0 if major else 1.0, true)
		if major:
			_text(str(roundi(fraction * limit)), center + direction * 46.0 + Vector2(0, 5), 14, tick_color)
	draw_line(center - Vector2.from_angle(end_angle) * 10.0, center + Vector2.from_angle(end_angle) * 59.0, accent, 3.0, true)
	draw_circle(center, 5.0, accent, true, -1.0, true)
	_text(unit, center + Vector2(0, 57), 16, MUTED)


func _indicator(center: Vector2, right: bool, color: Color) -> void:
	# Geometry avoids color-font/emoji substitution ignoring the inactive tint.
	var arrow := PackedVector2Array([Vector2(10, -4), Vector2(0, -4), Vector2(0, -10), Vector2(-12, 0), Vector2(0, 10), Vector2(0, 4), Vector2(10, 4)])
	for i in arrow.size():
		arrow[i].x *= -1.0 if right else 1.0
		arrow[i] += center
	draw_colored_polygon(arrow, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(RESOLUTION)), INK)
	var left_color := Color("63f1a6") if readings.get("left", false) else EDGE
	var right_color := Color("63f1a6") if readings.get("right", false) else EDGE
	_indicator(Vector2(250, 16), false, left_color)
	_indicator(Vector2(390, 16), true, right_color)
	var light_mode := int(readings.get("light_mode", 0))
	_text("FERN" if light_mode == 2 else ("ABL" if light_mode == 1 else ""), Vector2(320, 23), 18, BLUE if light_mode == 2 else Color("63f1a6"))
	if _digital:
		var lit := clampi(ceili(_rpm / _rpm_max * 24.0), 0, 24)
		for i in 24:
			var color := RED if float(i + 1) / 24.0 * _rpm_max >= _redline else (AMBER if i >= 17 else BLUE)
			draw_rect(Rect2(44 + i * 23, 140, 20, 6), color if i < lit else EDGE)
		_text("%d U/min" % roundi(_rpm), Vector2(142, 101), 24, AMBER)
		_text(str(roundi(_speed)), Vector2(320, 108), 56, WHITE)
		_text("km/h", Vector2(320, 130), 18, MUTED)
		_text(_gear, Vector2(510, 110), 46, BLUE)
		_text("AUTO" if readings.get("automatic", true) else "MANUELL", Vector2(510, 134), 17, MUTED)
	else:
		# Keep dials subordinate to the speed/gear and bottom warning strip.
		draw_set_transform(Vector2(18, 9), 0, Vector2(0.84, 0.84))
		_dial(Vector2(152, 91), _speed, 280.0, 7, "km/h", BLUE, INF)
		draw_set_transform(Vector2(82, 9), 0, Vector2(0.84, 0.84))
		_dial(Vector2(488, 91), _rpm * 0.001, _rpm_max * 0.001, roundi(_rpm_max * 0.001), "×1000 U/min", AMBER, _redline * 0.001)
		draw_set_transform(Vector2.ZERO)
		_text(str(roundi(_speed)), Vector2(320, 90), 43, WHITE)
		_text("km/h", Vector2(320, 111), 16, MUTED)
		_text(("A " if readings.get("automatic", true) else "M ") + _gear, Vector2(320, 139), 27, BLUE)
	draw_line(Vector2(35, 151), Vector2(605, 151), EDGE, 1.0)
	var fuel := float(readings.get("fuel", 0))
	var coolant := float(readings.get("coolant", 20))
	_text("%.1f l" % fuel, Vector2(132, 176), 22, AMBER if fuel < float(readings.get("capacity", 50)) * 0.1 else WHITE)
	_text("%.0f °C" % coolant, Vector2(508, 176), 22, RED if coolant >= 115 else WHITE)
	var warning: Dictionary = readings.get("warning", {"text": "", "urgent": false})
	var warning_text := str(warning["text"])
	if warning_text.is_empty():
		var assists: Array[String] = []
		if not readings.get("abs", true): assists.append("ABS AUS")
		if not readings.get("tcs", true): assists.append("TCS AUS")
		warning_text = " / ".join(assists)
	_text(warning_text, Vector2(320, 45), 17, RED if warning.get("urgent", false) else AMBER)
