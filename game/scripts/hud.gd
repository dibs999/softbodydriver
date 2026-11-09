extends Control
## Quiet driving HUD. Detailed mechanical telemetry is an explicit F2 overlay.
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
var _toast := ""
var _toast_t := 0.0
var font: Font
var _panel_style: StyleBoxFlat

const TEXT := Color("edf4f5")
const MUTED := Color("98b0b8")
const ACCENT := Color("71e0cb")
const AMBER := Color("ffc378")
const RED := Color("ff756c")
const STATUS := {
	"ENGINE SEIZED": "Motor festgelaufen", "OUT OF FUEL": "Tank leer",
	"DRIVESHAFT BROKEN": "Antriebswelle gebrochen", "HEAD GASKET BLOWN": "Zylinderkopfdichtung defekt",
	"OVERHEATING": "Motor überhitzt", "LOW OIL PRESSURE": "Öldruck zu niedrig",
	"LOW COOLANT": "Zu wenig Kühlmittel", "COOLANT LEAK": "Kühlmittelverlust",
	"OIL LEAK": "Ölverlust", "FUEL LEAK": "Kraftstoffverlust", "ENGINE OFF": "Motor aus · I starten",
	"GEARBOX FAILED": "Getriebe ausgefallen · kein Vortrieb", "CLUTCH FAILED": "Kupplung verschlissen · kein Vortrieb",
	"CLUTCH OVERHEATING": "Kupplung überhitzt · entlasten",
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.025, 0.06, 0.075, 0.92)
	_panel_style.border_color = Color(0.50, 0.80, 0.80, 0.16)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(16)

func toast(message: String) -> void:
	_toast = message
	_toast_t = 3.0

func set_driving_help(on: bool) -> void:
	show_help = on

func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 240: _frame_ms.remove_at(0)
	if is_instance_valid(vehicle):
		_t = vehicle.get_telemetry()
		_rpm_disp = lerpf(_rpm_disp, float(_t["rpm"]), 1.0 - exp(-delta * 16))
		_kmh_disp = lerpf(_kmh_disp, float(_t["speed_kmh"]), 1.0 - exp(-delta * 12))
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
	_toast_t = maxf(0, _toast_t - delta)
	queue_redraw()

func _text(p: Vector2, value: String, size_px := 14, color := TEXT) -> void:
	draw_string(font, p, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _right(p: Vector2, value: String, size_px := 14, color := TEXT) -> void:
	p.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_text(p, value, size_px, color)

func _panel(rect: Rect2) -> void:
	draw_style_box(_panel_style, rect)

func _bar(p: Vector2, width: float, fraction: float, color := ACCENT) -> void:
	draw_style_box(_panel_style, Rect2(p, Vector2(width, 5)))
	draw_line(p + Vector2(0, 2.5), p + Vector2(width * clampf(fraction, 0, 1), 2.5), color, 4.0, true)

func _draw() -> void:
	if _t.is_empty():
		return
	var vs := get_viewport_rect().size
	var scale_ui := minf(1.0, minf(vs.x / 960.0, vs.y / 600.0))
	var canvas := vs / scale_ui
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_ui)
	_panel(Rect2(20, 20, 312, 66))
	draw_line(Vector2(36, 36), Vector2(36, 68), ACCENT, 3)
	_text(Vector2(50, 47), String(info.get("name", "Fahrzeug")), 17)
	_text(Vector2(50, 69), "%s   /   %s" % [camera_name, activity.MODES[activity.mode] if activity else "Freie Fahrt"], 12, MUTED)
	_right(Vector2(canvas.x - 22, 38), "Start  Pause · Aktivitäten · Steuerung" if DriverPrompts.using_gamepad else "F1  Hilfe     F2  Diagnose     F3  Aktivitäten     Esc  Pause", 12, TEXT)
	if not cockpit or not in_dash_instruments:
		_drive_card(canvas)
	if lesson and lesson.visible_in_hud() and not show_help and not show_diagnostics:
		_panel(Rect2(20, 98, 460, 138))
		_text(Vector2(36, 123), "FAHREINFÜHRUNG", 12, ACCENT)
		draw_multiline_string(font, Vector2(36, 148), lesson.text, HORIZONTAL_ALIGNMENT_LEFT, 428, 14, 2, TEXT)
		draw_string(font, Vector2(36, 192), lesson.status, HORIZONTAL_ALIGNMENT_LEFT, 428, 11, MUTED)
		_bar(Vector2(36, 204), 428, lesson.progress)
		_text(Vector2(36, 224), "%s · Einführung ausblenden oder neu starten" % DriverPrompts.hint("menu"), 11, MUTED)
	_warnings(canvas)
	if is_instance_valid(equipment):
		var label: String = equipment.status_text()
		_panel(Rect2(20, canvas.y - 282, 580, 34))
		_text(Vector2(34, canvas.y - 260), label, 12, ACCENT)
	if is_instance_valid(weather):
		var status: String = weather.get_status()
		var width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24
		_panel(Rect2(canvas.x - width - 14, 44, width, 28))
		_right(Vector2(canvas.x - 26, 63), status, 12, TEXT)
	if activity and activity.mode > 0 and not show_diagnostics and not show_help:
		var p := Vector2(canvas.x - 390, 82)
		_panel(Rect2(p, Vector2(370, 91)))
		_text(p + Vector2(16, 24), activity.MODES[activity.mode].to_upper(), 12, ACCENT)
		_text(p + Vector2(16, 47), activity.message, 13)
		var best_label := "Best: %d Pkt." % activity.best if activity.mode == 2 else "Best: %.2f s" % activity.best
		_text(p + Vector2(16, 72), "Start · Aktivitätenmenü" if DriverPrompts.using_gamepad else "F3 Wechseln · F4 " + ("Abbruch" if activity.active else "Start"), 11, MUTED)
		if activity.best > 0: _right(p + Vector2(354, 72), best_label, 11, ACCENT)
	if show_diagnostics:
		_diagnostics(canvas)
	if show_help:
		_help(canvas)
	if world and (world.paused or world.time_scale < 0.99):
		var label := "SIMULATION PAUSIERT" if world.paused else "ZEITLUPE  ×%.2f" % world.time_scale
		_text(Vector2(36, 110), label, 14, AMBER)
	if _toast_t > 0:
		var width := minf(canvas.x - 40, font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 36)
		var p := Vector2((canvas.x - width) * 0.5, 102)
		_panel(Rect2(p, Vector2(width, 40)))
		_text(p + Vector2(18, 26), _toast, 15)
	draw_set_transform(Vector2.ZERO)

func _drive_card(canvas: Vector2) -> void:
	var p := Vector2(20, canvas.y - 238)
	_panel(Rect2(p, Vector2(338, 218)))
	_text(p + Vector2(18, 24), "FAHRINSTRUMENTE", 11, MUTED)
	_right(p + Vector2(320, 24), "AUTO" if vehicle.is_automatic() else "MANUELL", 11, ACCENT)
	var center := p + Vector2(115, 116)
	var redline := maxf(1000.0, float(info.get("redline_rpm", 6500)))
	var fraction := clampf(_rpm_disp / redline, 0.0, 1.15)
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	draw_arc(center, 78, start, start + sweep, 64, Color(1, 1, 1, 0.12), 7, true)
	draw_arc(center, 78, start + sweep * 0.85, start + sweep, 16, RED.darkened(0.45), 7, true)
	if fraction > 0.001:
		draw_arc(center, 78, start, start + sweep * minf(fraction, 1), 64, RED if fraction > 0.9 else ACCENT, 5, true)
	for i in range(int(redline / 1000.0) + 1):
		var angle := start + sweep * (i * 1000.0 / redline)
		var ray := Vector2(cos(angle), sin(angle))
		draw_line(center + ray * 65, center + ray * 70, MUTED, 1.5, true)
		var label := str(i)
		_text(center + ray * 55 - Vector2(3, -4), label, 10, MUTED)
	var speed := str(roundi(absf(_kmh_disp)))
	_text(center + Vector2(-font.get_string_size(speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x / 2, 15), speed, 42)
	_text(center + Vector2(-16, 34), "km/h", 11, MUTED)
	_text(p + Vector2(60, 202), "%d U/min" % (roundi(_rpm_disp / 50) * 50), 12, MUTED)
	var gear := int(_t["gear"])
	_text(p + Vector2(244, 92), "R" if gear < 0 else ("N" if gear == 0 else str(gear)), 46, ACCENT)
	_text(p + Vector2(224, 114), "GANG", 10, MUTED)
	_text(p + Vector2(218, 144), "%.1f l" % float(_t["fuel_l"]), 17)
	_text(p + Vector2(218, 167), "%.0f °C" % float(_t["coolant_temp"]), 15, AMBER if float(_t["coolant_temp"]) > 110 else MUTED)
	var aids := "TCS" if vehicle.get_tcs() else "TCS AUS"
	aids += "  ·  ABS" if vehicle.get_abs() else "  ·  ABS AUS"
	_text(p + Vector2(210, 199), aids, 10, AMBER if bool(_t["tcs_active"]) or bool(_t["abs_active"]) else MUTED)


func _warnings(canvas: Vector2) -> void:
	var messages: Array[String] = []
	var status: String = _t.get("status", "")
	if not status.is_empty(): messages.append("Motor aus · %s starten" % DriverPrompts.hint("ignition") if status == "ENGINE OFF" else STATUS.get(status, status))
	var names := ["vorne links", "vorne rechts", "hinten links", "hinten rechts"]
	var pressure: Array = _t.get("tire_pressure", [])
	for i in mini(4, pressure.size()):
		if pressure[i] < 8.0 or bool(_t["wheel_burst"][i]):
			messages.append("Reifen platt · " + names[i])
		elif pressure[i] < 19.0:
			messages.append("Reifendruck niedrig · " + names[i])
	if messages.is_empty(): return
	var p := Vector2(20, 250 if lesson and lesson.visible_in_hud() else 132)
	var width := minf(canvas.x - 40, 440)
	_panel(Rect2(p, Vector2(width, 61 + mini(3, messages.size()) * 23)))
	_text(p + Vector2(16, 23), "FAHRZEUG PRÜFEN   ·   F2 DETAILS", 11, AMBER)
	for i in mini(3, messages.size()):
		_text(p + Vector2(16, 47 + i * 23), messages[i], 14, RED)
	var advice := "Langsam anhalten · %s: Bergung zum Service" % DriverPrompts.hint("menu")
	if status == "CLUTCH OVERHEATING": advice = "Gas wegnehmen · Kupplung schließen und abkühlen lassen"
	elif status == "OVERHEATING": advice = "Anhalten · %s Motor aus · Kühlung prüfen" % DriverPrompts.hint("ignition")
	elif status == "ENGINE OFF": advice = "%s Motor starten · %s Kupplung (manuell)" % [DriverPrompts.hint("ignition"), DriverPrompts.hint("clutch")]
	_text(p + Vector2(16, 48 + mini(3, messages.size()) * 23), advice, 11, MUTED)

func _row(p: Vector2, title: String, value: String, fraction: float, color := ACCENT) -> void:
	_text(p, title, 13, MUTED)
	_right(p + Vector2(242, 0), value, 13, color)
	_bar(p + Vector2(0, 9), 242, fraction, color)

func _diagnostics(canvas: Vector2) -> void:
	var p := Vector2((canvas.x - 610) * 0.5, maxf(94, (canvas.y - 400) * 0.5))
	_panel(Rect2(p, Vector2(610, 400)))
	_text(p + Vector2(22, 31), "FAHRZEUGZUSTAND", 19)
	_right(p + Vector2(588, 29), "F2  Schließen", 12, MUTED)
	draw_line(p + Vector2(22, 47), p + Vector2(588, 47), Color(1, 1, 1, 0.12))
	_text(p + Vector2(22, 73), "ANTRIEB & KÜHLUNG", 11, ACCENT)
	_row(p + Vector2(22, 102), "Motor", "%d %% intakt" % roundi(100 * (1 - float(_t["engine_damage"]))), 1 - float(_t["engine_damage"]))
	var cw := float(_t.get("clutch_wear", 0))
	var ct := float(_t.get("clutch_temp", 45))
	_row(p + Vector2(22, 143), "Kupplung", "%d %% · %.0f °C" % [roundi((1 - cw) * 100), ct], 1 - cw, RED if cw > 0.65 or ct > 200 else ACCENT)
	var gd := float(_t.get("gearbox_damage", 0))
	_row(p + Vector2(22, 184), "Getriebe", "%d %% intakt" % roundi((1 - gd) * 100), 1 - gd, RED if gd > 0.5 else ACCENT)
	_row(p + Vector2(22, 225), "Kühlmittel", "%.0f °C · %.0f %%" % [_t["coolant_temp"], 100 * float(_t["coolant_level"])], float(_t["coolant_level"]), RED if float(_t["coolant_temp"]) > 115 else ACCENT)
	_row(p + Vector2(22, 266), "Motoröl", "%.0f °C · %.1f bar" % [_t["oil_temp"], _t["oil_pressure"]], float(_t["oil_level"]))
	_text(p + Vector2(320, 73), "REIFEN  /  DRUCK · TEMPERATUR", 11, ACCENT)
	var names := ["Vorne links", "Vorne rechts", "Hinten links", "Hinten rechts"]
	for i in 4:
		var pressure := float(_t["tire_pressure"][i])
		var wear := float(_t["tire_wear"][i])
		var label := "PLATT" if pressure < 8 or bool(_t["wheel_burst"][i]) else "%.1f bar · %.0f °C" % [pressure * 0.0689476, _t["tire_temp"][i]]
		_row(p + Vector2(320, 102 + i * 41), names[i], label, 1 - wear, RED if pressure < 19 or wear > 0.7 else ACCENT)
	_text(p + Vector2(320, 278), "Balken: verbleibendes Reifenprofil", 11, MUTED)
	_text(p + Vector2(22, 318), "Shift  Kupplung    Q / E  Schalten    M  Getriebemodus", 13, TEXT)
	_text(p + Vector2(22, 340), "Rücktaste  Fahrzeug vollständig reparieren", 13, MUTED)
	_text(p + Vector2(22, 365), "%d FPS · %.1f ms Ø / %.1f ms P95 · %d Zeichenaufrufe" % [Engine.get_frames_per_second(), _mean_ms, _p95_ms, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)], 12, MUTED)
	_text(p + Vector2(22, 385), "Physik %d Hz · %.0f %% Echtzeit · Messfenster bis 240 Bilder" % [_stats.get("physics_hz", 2000), 100 * float(_stats.get("realtime_factor", 1))], 11, MUTED)

func _help(canvas: Vector2) -> void:
	var p := Vector2((canvas.x - 610) * 0.5, (canvas.y - 496) * 0.5)
	_panel(Rect2(p, Vector2(610, 496)))
	_text(p + Vector2(24, 35), "DEINE STEUERUNG", 20)
	_right(p + Vector2(586, 33), "F1  Schließen", 12, MUTED)
	if DriverPrompts.using_gamepad:
		draw_multiline_string(font, p + Vector2(24, 82), DriverPrompts.control_summary(), HORIZONTAL_ALIGNMENT_LEFT, 560, 18, -1, TEXT)
		draw_multiline_string(font, p + Vector2(24, 368), "Start öffnet auch Aktivitäten, Wetter und Bergung.\nTanken und Reparatur: im markierten Servicebereich anhalten,\nMotor ausschalten und D-Pad halten.", HORIZONTAL_ALIGNMENT_LEFT, 560, 15, -1, MUTED)
		return
	var lines := [
		["W / S  ·  A / D", "Gas & Bremse / Rückwärts  ·  Lenken"],
		["Leertaste", "Handbremse"], ["Shift  ·  Q / E  ·  M", "Kupplung  ·  Schalten  ·  Automatik / Manuell"],
		["C  ·  rechte Maus", "Kamera wechseln  ·  Umsehen, Mausrad zoomt"],
		["T  ·  Z  ·  I", "Traktionskontrolle  ·  ABS  ·  Motor starten"],
		["R  ·  Rücktaste", "Zurücksetzen  ·  Reparieren"],
		["K / N  ·  F2", "Karte / Minikarte  ·  Fahrzeugdiagnose"],
		["F3  ·  F4", "Aktivität wählen  ·  Start / Abbruch"],
		["J  ·  P  ·  Tab  ·  B", "Zeitlupe  ·  Physikpause  ·  Fahrzeug  ·  Debug"],
		["L  ·  , / .  ·  H", "Licht  ·  Blinker links / rechts  ·  Warnblinker"],
		["F / G halten  ·  O", "Tanken / Service (Motor aus)  ·  Haube entriegeln"],
		["U  ·  Shift+U", "Fahrer- / Beifahrertür im Stand öffnen / schließen"],
		["F7  ·  F8", "Wetter wechseln  ·  Tageszeit wechseln"],
		["Gamepad", "RT/LT Gas/Bremse · Stick lenkt · A Handbremse"],
	]
	for i in lines.size():
		_text(p + Vector2(24, 76 + i * 27), lines[i][0], 13, ACCENT)
		_text(p + Vector2(211, 76 + i * 27), lines[i][1], 13, TEXT)
