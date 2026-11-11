extends SceneTree
## Pursuit (Verfolgungsjagd): an interceptor with flashing light bar starts 50 m behind the player,
## waits out the countdown, then drives up and arrests a player who stays put; with the police far
## out of reach the player gets away after 8 s and earns gold. Afterwards the police car is gone.
## godot --headless -s res://tests/pursuit_test.gd
const STEP := 0.05

var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
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

func _step(scene: Node, activity: Node) -> void:
	for v in scene.ai.keys():
		scene.ai[v].update(STEP)
	scene.world.step_blocking(STEP)
	activity._process(STEP)

func _run(scene: Node) -> void:
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	var activity: Node = scene.activity
	activity.set_process(false)
	activity.records_path = "user://pursuit_test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.records_path))
	check(6 in activity.available_modes(), "Pursuit is offered on the map")
	var base_vehicles: int = scene.vehicles.size()
	activity.mode = 6
	activity.start()
	check(activity.police != null, "A police car joins the run")
	if activity.police == null:
		return
	var cop: SBVehicle = activity.police.vehicle
	var beacons := cop.get_node_or_null("Beacons")
	check(beacons != null and beacons.active, "The interceptor's light bar and siren are on")
	check(cop.has_meta("light_bar") and (cop.get_meta("light_bar")["size"] as Vector3).z > 0.5, "The light bar is found on the model")
	var player: SBVehicle = scene.player
	for i in 40:   # placement and countdown
		player.set_input(0, 1, 0, 1)
		_step(scene, activity)
	var start_gap := player.get_position_ws().distance_to(cop.get_position_ws())
	print("  gap after the countdown: %.1f m" % start_gap)
	check(start_gap > 35.0 and start_gap < 70.0, "The police starts some 50 m behind")
	# The player stays put: the police drives up and makes the arrest.
	var t := 0.0
	while activity.active and t < 60.0:
		player.set_input(0, 1, 0, 1)
		_step(scene, activity)
		t += STEP
		if fmod(t, 4.0) < STEP:
			print("    t %.0f gap %.1f m police %.0f km/h dir %d idx %d at %s msg %s" % [t, player.get_position_ws().distance_to(cop.get_position_ws()), cop.get_speed_kmh(), activity.police.dir, activity.police.idx, cop.get_position_ws(), activity.message])
	var result: Dictionary = activity.last_result
	print("  after %.1f s: escaped=%s medal=%d" % [t, str(result.get("escaped")), int(result.get("medal", -1))])
	check(not activity.active and result.get("mode", -1) == 6 and not bool(result.get("escaped", true)), "A stationary player is arrested")
	check(int(result.get("medal", -1)) == 0, "An arrest earns no medal")
	check(scene.vehicles.size() == base_vehicles and activity.police == null, "The police car is removed after the run")
	# Second run: the police is parked far away; the gap holds and the player gets away.
	activity.start()
	cop = activity.police.vehicle
	for i in 40:
		player.set_input(0, 1, 0, 1)
		_step(scene, activity)
	activity.police.hold = true
	# Park it 400 m along the start straight's back direction (open ground on the proving ground).
	var far := player.get_position_ws() - player.get_forward() * 400.0
	cop.reset_to(Transform3D(Basis.IDENTITY, far + Vector3.UP * 0.8))
	t = 0.0
	while activity.active and t < 30.0:
		player.set_input(0, 1, 0, 1)
		activity.police.hold = true
		_step(scene, activity)
		t += STEP
	result = activity.last_result
	print("  second run: escaped=%s medal=%d after %.1f s" % [str(result.get("escaped")), int(result.get("medal", -1)), float(result.get("elapsed", 0.0))])
	check(bool(result.get("escaped", false)), "With the police out of reach the player escapes")
	check(int(result.get("medal", 0)) == 3, "A quick escape earns gold")
	check(activity.medal_for(6, {"escaped": true, "elapsed": 80.0}) == 2 and activity.medal_for(6, {"escaped": true, "elapsed": 179.0}) == 1, "Medals by escape time")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.records_path))
