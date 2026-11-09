extends Control
## In-world centre display, rendered only in the cockpit; no extra 3D viewport.
const Instruments := preload("res://scripts/instrument_cluster.gd")
var telemetry: Dictionary = {}
var info: Dictionary = {}
var controls: Dictionary = {}
var warning: Dictionary = {"text": "", "urgent": false}

func set_readings(values: Dictionary, vehicle_info: Dictionary, switches: Dictionary) -> void:
	telemetry = values
	info = vehicle_info
	controls = switches
	warning = Instruments.warning_for(telemetry, info, controls)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512, 280), Color("101d25"))
	var font := ThemeDB.fallback_font
	var white := Color("e7f0f1")
	var accent := Color("71e0cb")
	draw_string(font, Vector2(26, 36), str(info.get("name", "FAHRZEUG")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 460, 23, accent)
	var lights := int(controls.get("light_mode", 0))
	var switches := "%s · %s · TCS %s · ABS %s" % [
		["LICHT AUS", "ABBLENDLICHT", "FERNLICHT"][clampi(lights, 0, 2)],
		"AUTO" if controls.get("automatic", true) else "MANUELL",
		"AN" if controls.get("tcs", true) else "AUS", "AN" if controls.get("abs", true) else "AUS"]
	draw_string(font, Vector2(26, 62), switches, HORIZONTAL_ALIGNMENT_LEFT, 460, 15, Color("92aab4"))
	draw_line(Vector2(26, 74), Vector2(486, 74), Color("344750"), 2)
	var rows := [
		["KÜHLMITTEL", "%.0f °C" % float(telemetry.get("coolant_temp", 0))],
		["KRAFTSTOFF", "%.1f l" % float(telemetry.get("fuel_l", 0))],
		["VERBRAUCH", "%.1f l/h" % float(telemetry.get("fuel_rate", 0))],
	]
	for i in rows.size():
		draw_string(font, Vector2(26, 114 + i * 46), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("92aab4"))
		draw_string(font, Vector2(350, 114 + i * 46), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 27, white)
	var text := str(warning["text"])
	draw_rect(Rect2(0, 231, 512, 49), Color("693a2f") if warning["urgent"] else Color("1a383b"))
	var advice := "  ·  ANHALTEN" if text == "TÜR OFFEN" else "  ·  SERVICE"
	draw_string(font, Vector2(26, 263), text + (advice if warning["urgent"] else "") if not text.is_empty() else "SYSTEME BEREIT", HORIZONTAL_ALIGNMENT_LEFT, 460, 21, white)
