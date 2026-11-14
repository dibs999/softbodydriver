extends Node
## Gamepad rumble from what the car does: a hit is a hard jolt on the heavy motor, scaled with the
## impact; ABS chatters, loose ground and a scraping body buzz the light motor; wheelspin and the
## rev limiter add a fine vibration. Only the pad that drove last rumbles, nothing while paused.
## Settings → Steuerung switches it off.
const DriverPrompts := preload("res://scripts/driver_prompts.gd")
const TICK := 0.05
var vehicle: SBVehicle
var world: SBWorld
var effects: Node
var enabled := true
var strong := 0.0      # current heavy-motor level, 0..1
var weak := 0.0        # current light-motor level, 0..1
var _jolt := 0.0
var _timer := 0.0
var _phase := 0.0
var _device := -1


## Called with the same impact measure the audio and camera use.
func impact(strength: float) -> void:
	_jolt = clampf(maxf(_jolt, strength / 90.0), 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		_device = event.device


func levels(t: Dictionary, delta: float) -> Vector2:
	_phase += delta
	var kmh := absf(float(t.get("speed_kmh", 0.0)))
	var heavy := _jolt
	var light := 0.0
	if bool(t.get("abs_active", false)):
		light = maxf(light, 0.55 if fmod(_phase, 0.08) < 0.04 else 0.15)   # ~12 Hz pedal chatter
	if float(t.get("scrape", 0.0)) > 0.05:
		light = maxf(light, clampf(float(t["scrape"]), 0.2, 0.7))
	if is_instance_valid(effects) and kmh > 5.0:
		var loose := 0
		for kind in effects.get("wheel_surfaces"):
			if kind in ["gravel", "sand", "grass"]: loose += 1
		light = maxf(light, loose / 4.0 * clampf(kmh / 70.0, 0.1, 0.45))
	var slips: PackedFloat32Array = vehicle.get_wheel_slip() if is_instance_valid(vehicle) else PackedFloat32Array()
	var slip := 0.0
	for s in slips: slip = maxf(slip, s)
	if slip > 0.35 and kmh > 3.0:
		light = maxf(light, clampf((slip - 0.35) * 0.6, 0.0, 0.35))
	var rpm := float(t.get("rpm", 0.0))
	var redline := float(vehicle.get_info().get("redline_rpm", 7000.0)) if is_instance_valid(vehicle) else 7000.0
	if bool(t.get("running", false)) and rpm > redline * 0.98:
		light = maxf(light, 0.3)
	_jolt = move_toward(_jolt, 0.0, delta * 3.5)   # a hit fades over ~0.3 s
	return Vector2(clampf(light, 0, 1), clampf(heavy, 0, 1))


func _process(delta: float) -> void:
	var pad: bool = DriverPrompts.using_gamepad and enabled and bool(Game.settings.get("rumble", true))
	if not pad or not is_instance_valid(vehicle) or (is_instance_valid(world) and world.paused):
		_stop()
		return
	var l := levels(vehicle.get_telemetry(), delta * (world.time_scale if is_instance_valid(world) else 1.0))
	_timer -= delta
	if _timer > 0.0 and absf(l.x - weak) < 0.08 and absf(l.y - strong) < 0.08:
		return
	_timer = TICK
	weak = l.x
	strong = l.y
	var device := _device if _device >= 0 else (Input.get_connected_joypads()[0] if not Input.get_connected_joypads().is_empty() else -1)
	if device < 0:
		return
	if weak < 0.02 and strong < 0.02:
		Input.stop_joy_vibration(device)
	else:
		Input.start_joy_vibration(device, weak, strong, TICK * 3.0)


func _stop() -> void:
	if weak > 0.0 or strong > 0.0:
		for d in Input.get_connected_joypads():
			Input.stop_joy_vibration(d)
	weak = 0.0
	strong = 0.0


func _exit_tree() -> void:
	_stop()
