extends Control
## In-world centre display, rendered only in the cockpit.
var telemetry: Dictionary = {}

func _draw() -> void:
	draw_rect(Rect2(0, 0, 512, 280), Color("101d25"))
	var font := ThemeDB.fallback_font
	var white := Color("e7f0f1")
	var accent := Color("71e0cb")
	draw_string(font, Vector2(26, 42), "KESTREL  /  DRIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, accent)
	draw_line(Vector2(26, 56), Vector2(486, 56), Color("344750"), 2)
	var rows := [
		["KÜHLMITTEL", "%.0f °C" % float(telemetry.get("coolant_temp", 0))],
		["KRAFTSTOFF", "%.1f l" % float(telemetry.get("fuel_l", 0))],
		["VERBRAUCH", "%.1f l/h" % float(telemetry.get("fuel_rate", 0))],
	]
	for i in rows.size():
		draw_string(font, Vector2(26, 100 + i * 49), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("92aab4"))
		draw_string(font, Vector2(350, 100 + i * 49), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, white)
	var warning := not String(telemetry.get("status", "")).is_empty()
	draw_rect(Rect2(0, 231, 512, 49), Color("693a2f") if warning else Color("1a383b"))
	draw_string(font, Vector2(26, 263), "FAHRZEUG PRÜFEN  /  F2" if warning else "SYSTEME BEREIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, white)
