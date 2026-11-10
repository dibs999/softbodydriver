extends SceneTree
## Tuning from the pause menu: tyre pressures per axle reach the tyres, the front brake share
## moves braking work between the axles, and the menu sliders apply and show the values.
## godot --headless -s res://tests/tuning_test.gd
const STEP := 0.02

var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	if frame < 5:
		return false
	_run(scene)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true

func _steps(world: SBWorld, car: SBVehicle, seconds: float, throttle: float, brake: float) -> void:
	for i in int(seconds / STEP):
		car.set_input(throttle, brake, 0.0, 0.0)
		world.step_blocking(STEP)

## Mean wheel slip of the front and the rear axle while braking from 70 km/h.
func _brake_slip(world: SBWorld, car: SBVehicle, start: Transform3D) -> Vector2:
	car.reset_to(start)
	world.step_blocking(0.5)
	var t := 0.0
	while car.get_speed_kmh() < 70.0 and t < 25.0:
		_steps(world, car, 0.1, 1.0, 0.0)
		t += 0.1
	var front := 0.0
	var rear := 0.0
	var samples := 0
	for i in int(0.6 / STEP):
		car.set_input(0.0, 0.55, 0.0, 0.0)
		world.step_blocking(STEP)
		var slip := car.get_wheel_slip()
		front += (slip[0] + slip[1]) * 0.5
		rear += (slip[2] + slip[3]) * 0.5
		samples += 1
	_steps(world, car, 3.0, 0.0, 1.0)
	return Vector2(front, rear) / samples

func _run(scene: Node) -> void:
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	var car: SBVehicle = scene.player
	car.set_abs(false)
	var tuning: Dictionary = car.get_tuning()
	check(absf(float(tuning["front_psi"]) - float(tuning["default_psi"])) < 0.01 and float(tuning["brake_bias"]) > 0.5,
		"Defaults are reported (%.1f psi, %.0f %% front)" % [tuning["front_psi"], float(tuning["brake_bias"]) * 100.0])
	# Pressure.
	car.set_tire_pressure(20.0, 44.0)
	_steps(world, car, 1.0, 0.0, 1.0)
	var p: Array = car.get_telemetry()["tire_pressure"]
	print("  pressures ", p)
	check(p[0] < 24.0 and p[1] < 24.0 and p[2] > 40.0 and p[3] > 40.0, "Axle pressures reach the tyres")
	car.set_tire_pressure(float(tuning["default_psi"]), float(tuning["default_psi"]))
	_steps(world, car, 0.5, 0.0, 1.0)
	# Brake share.
	var start := Transform3D(Basis(Vector3.UP, 0.0), Vector3(-150, 0.6, -5))
	car.set_brake_bias(0.82)
	var nose := _brake_slip(world, car, start)
	car.set_brake_bias(0.45)
	var tail := _brake_slip(world, car, start)
	print("  slip front/rear  82 %% front: %.3f / %.3f   45 %% front: %.3f / %.3f" % [nose.x, nose.y, tail.x, tail.y])
	check(nose.x > tail.x and tail.y > nose.y, "More front brake share works the front tyres harder, less works the rear")
	# Pause menu sliders.
	car.set_brake_bias(0.68)
	scene._sync_tuning()
	check(absf(scene._tune_bias.value - 68.0) < 0.6, "Menu shows the current brake share")
	scene._tune_front.value = 26.0
	scene._tune_rear.value = 30.0
	var after: Dictionary = car.get_tuning()
	check(absf(float(after["front_psi"]) - 26.0) < 0.01 and absf(float(after["rear_psi"]) - 30.0) < 0.01, "Menu sliders apply the pressures")
