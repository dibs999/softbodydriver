extends Node
## One shared input-family tracker, independent of whichever menu/lesson is visible.
signal device_changed
static var using_gamepad := false
const KEYS := {
	"throttle": "W", "brake": "S", "steering": "A/D", "camera_next": "C",
	"ignition": "I", "headlights": "L", "wipers": "X", "toggle_gearbox": "M",
	"shift_down": "Q", "shift_up": "E", "clutch": "Shift",
	"handbrake": "Leertaste", "refuel": "F", "service_repair": "G",
	"cruise_control": "V",
	"menu": "Esc", "reset_vehicle": "R", "driver_door": "U", "passenger_door": "Shift+U", "cockpit_look": "rechte Maustaste + Maus",
}
const PAD := {
	"throttle": "RT", "brake": "LT", "steering": "linker Stick", "camera_next": "Y",
	"ignition": "Back", "headlights": "D-Pad ↑", "wipers": "Start → Wischer", "toggle_gearbox": "D-Pad ↓",
	"shift_down": "LB", "shift_up": "RB", "clutch": "X",
	"handbrake": "A", "refuel": "D-Pad ←", "service_repair": "D-Pad →",
	"cruise_control": "R3",
	"menu": "Start", "reset_vehicle": "B", "driver_door": "Start → Fahrertür", "passenger_door": "Start → Beifahrertür", "cockpit_look": "rechter Stick",
}

func _input(event: InputEvent) -> void:
	var previous := using_gamepad
	if event is InputEventJoypadButton and event.pressed:
		using_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		using_gamepad = true
	elif event is InputEventKey and event.pressed and not event.echo:
		using_gamepad = false
	elif event is InputEventMouseButton and event.pressed:
		using_gamepad = false
	if previous != using_gamepad:
		device_changed.emit()

static func hint(action: String) -> String:
	return str((PAD if using_gamepad else KEYS).get(action, action))

static func control_summary() -> String:
	var summary := "%s Gas · %s Bremse · %s lenken\n%s Handbremse · %s Kamera · %s Motor\n%s Getriebe Auto/Manuell · %s/%s schalten · %s Kupplung\n%s Licht · %s Wischer · %s tanken halten · %s reparieren halten\n%s Pause / Bergung · %s Sofort-Reset · %s Tempomat" % [
		hint("throttle"), hint("brake"), hint("steering"), hint("handbrake"), hint("camera_next"), hint("ignition"),
		hint("toggle_gearbox"), hint("shift_down"), hint("shift_up"), hint("clutch"), hint("headlights"),
		hint("wipers"), hint("refuel"), hint("service_repair"), hint("menu"), hint("reset_vehicle"), hint("cruise_control")]

	return summary + "\n" + ("Türen im Start-Menü · rechter Stick umsehen" if using_gamepad else "U Fahrertür · Shift+U Beifahrertür · rechte Maustaste umsehen")
