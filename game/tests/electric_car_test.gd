extends SceneTree
## The electric Kestrel: ready at a standstill without turning, pulls away, recuperates off the
## pedal (negative battery power, the charge rises), whines instead of running engine recordings,
## charges (not refuels) at the service bay, and keeps its motor out of the engine swap.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var energy := 0.0
var saw_regen := false

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "proving_grounds"
	g.selected_car = "res://cars/kestrel_ev.car.json"
	g.settings["traffic"] = false
	g.settings["career"] = false
	g.settings["automatic"] = true
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	var t := v.get_telemetry()
	match phase:
		0:
			if _sim() - mark < 1.5: return false
			check(bool(v.get_info()["electric"]), "The car reports an electric drive")
			check(bool(t["running"]) and float(t["rpm"]) < 50.0, "Ready at a standstill with the motor not turning (%.0f rpm)" % float(t["rpm"]))
			check(scene.audio.electric and scene.audio._engine_players.is_empty(), "It whines instead of playing engine recordings")
			check(scene.equipment._fill_verb() == "laden", "The service bay charges it")
			var ids: Array = root.get_node("Game").engine_catalogue().map(func(e): return e["id"])
			check(not ids.has("kestrel_ev") and ids.size() > 3, "The electric motor is not offered as a swap engine")
			Input.action_press("throttle", 1.0)
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 4.0: return false
			Input.action_release("throttle")
			check(v.get_speed_kmh() > 45.0, "It pulls away hard (%.0f km/h after 4 s)" % v.get_speed_kmh())
			check(scene.audio._whine > 0.01, "and the motor is heard")
			energy = float(t["fuel_l"])
			mark = _sim()
			phase = 2
		2:
			if float(t["fuel_rate"]) < -2.0: saw_regen = true
			if _sim() - mark < 2.5: return false
			check(saw_regen, "Off the pedal it recuperates (negative battery power)")
			check(float(t["fuel_l"]) > energy, "and the battery charge rises (%.4f -> %.4f kWh)" % [energy, float(t["fuel_l"])])
			Input.action_press("brake", 1.0)
			mark = _sim()
			phase = 3
		3:
			# Stop as soon as it stands (held longer, the automatic would select reverse).
			if absf(v.get_speed_kmh()) > 1.0 and _sim() - mark < 8.0: return false
			Input.action_release("brake")
			check(absf(v.get_speed_kmh()) < 2.0 and bool(t["running"]), "Braked to a standstill it stays ready, nothing stalls")
			print("ELECTRIC CAR TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
