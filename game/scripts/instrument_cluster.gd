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


func _draw() -> void:
	if _digital:
		draw_rect(Rect2(35, 21, 570, 140), INK)
		draw_rect(Rect2(35, 21, 570, 140), EDGE, false, 3.0)
		var lit := clampi(ceili(_rpm / _rpm_max * 24.0), 0, 24)
		for i in 24:
			var color := RED if float(i + 1) / 24.0 * _rpm_max >= _redline else (AMBER if i >= 17 else BLUE)
			draw_rect(Rect2(62 + i * 22, 39, 19, 22), color if i < lit else EDGE)
		_text("%d  U/min" % roundi(_rpm), Vector2(148, 116), 23, AMBER)
		_text(str(roundi(_speed)), Vector2(320, 121), 55, WHITE)
		_text("km/h", Vector2(320, 145), 19, MUTED)
		_text(_gear, Vector2(510, 122), 44, BLUE)
		_text("GANG", Vector2(510, 145), 16, MUTED)
		return

	_dial(Vector2(152, 91), _speed, 280.0, 7, "km/h", BLUE, INF)
	_dial(Vector2(488, 91), _rpm * 0.001, _rpm_max * 0.001, roundi(_rpm_max * 0.001), "×1000 U/min", AMBER, _redline * 0.001)
	draw_rect(Rect2(262, 30, 116, 122), INK)
	draw_rect(Rect2(262, 30, 116, 122), EDGE, false, 2.0)
	_text(str(roundi(_speed)), Vector2(320, 72), 36, WHITE)
	_text("km/h", Vector2(320, 91), 15, MUTED)
	_text("GANG  " + _gear, Vector2(320, 131), 22, BLUE)
