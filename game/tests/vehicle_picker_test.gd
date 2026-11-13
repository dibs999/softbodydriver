extends SceneTree
## In-game vehicle selection: the Kestrel is exchanged for the Vortex GT where it stands (the new car
## takes its place in the vehicle list and is the player), a Basalt SUV is parked in front, the
## exchange waits for a standstill, and removing parked cars takes only the parked one away.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var here := Vector3.ZERO
var count := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "proving_grounds"
	g.selected_car = "res://cars/kestrel_hatch.car.json"
	g.settings["traffic"] = false
	g.settings["career"] = false
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("swap_player_car"):
			scene = current_scene
			mark = _sim()
		return false
	match phase:
		0:
			if _sim() - mark < 1.5: return false
			here = scene.player.get_position_ws()
			count = scene.vehicles.size()
			print("  ", scene.swap_player_car("res://cars/vortex_gt.car.json"))
			var v: SBVehicle = scene.player
			check(str(v.get_info()["id"]) == "vortex_gt", "The player now drives the Vortex GT")
			check(v.get_position_ws().distance_to(here) < 2.0, "where the Kestrel stood")
			check(scene.vehicles.size() == count and scene.vehicles.has(v), "in the Kestrel's place in the vehicle list")
			check(root.get_node("Game").selected_car == "res://cars/vortex_gt.car.json", "and a restart keeps it")
			print("  ", scene.park_car_ahead("res://cars/basalt_suv.car.json"))
			check(scene.vehicles.size() == count + 1, "A Basalt SUV is parked in front")
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 2.0: return false
			check(bool(scene.world.get_stats().get("finite", true)), "Both settle without blowing up")
			Input.action_press("throttle", 1.0)
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 1.5: return false
			check(scene.swap_player_car("res://cars/kestrel_hatch.car.json") == "Zum Fahrzeugwechsel anhalten", "Swapping waits for a standstill")
			Input.action_release("throttle")
			print("  ", scene.remove_parked_cars())
			check(scene.vehicles.size() == count, "Removing parked cars takes the SUV away")
			check(str(scene.player.get_info()["id"]) == "vortex_gt", "and leaves the player's car")
			phase = 3
		3:
			print("VEHICLE PICKER TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
