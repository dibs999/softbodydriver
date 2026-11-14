extends Node
## Second gamepad layer on the Back (View/Select) button, so the signals a driver uses while
## moving have a button too: hold Back and press D-pad ← / → for the indicators, ↑ for the hazard
## lights, and hold ↓ to look back. A Back press on its own still switches the engine on and off,
## sent when the button is released without a combo.
const LAYER := {
	JOY_BUTTON_DPAD_LEFT: "indicator_left",
	JOY_BUTTON_DPAD_RIGHT: "indicator_right",
	JOY_BUTTON_DPAD_UP: "hazards",
	JOY_BUTTON_DPAD_DOWN: "look_back",
}
const HOLD_ACTIONS := ["look_back"]
var held := false
var _used := false


func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadButton:
		return
	var button: int = event.button_index
	if button == JOY_BUTTON_BACK:
		get_viewport().set_input_as_handled()
		if event.pressed:
			held = true
			_used = false
		elif held:
			held = false
			if not _used:
				_send("ignition", true)
				_send("ignition", false)
			for action in HOLD_ACTIONS:
				if Input.is_action_pressed(action):
					_send(action, false)
		return
	if not held or not LAYER.has(button):
		return
	# The D-pad's own actions (lights, gearbox, fuel, repair) do not fire while the layer is held:
	# the event is consumed, and the held state Input already gave its actions (fuel and repair are
	# polled while held) is taken back.
	get_viewport().set_input_as_handled()
	for base in InputMap.get_actions():
		if Input.is_action_pressed(base) and InputMap.action_has_event(base, event):
			Input.action_release(base)
	var action: String = LAYER[button]
	if event.pressed:
		_used = true
		_send(action, true)
	elif action in HOLD_ACTIONS:
		_send(action, false)


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
