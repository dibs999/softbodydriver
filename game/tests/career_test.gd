extends SceneTree
## Career mode: activities pay by mode and medal, a clean car costs nothing to repair and a damaged
## one does, the balance cannot be overdrawn and survives a profile reload; in the game an
## instant repair charges towing plus the bill (refused when broke), and with the career off
## everything stays free.
## godot --headless -s res://tests/career_test.gd
const Career := preload("res://scripts/career.gd")
const Progress := preload("res://scripts/player_progress.gd")
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	# Rules.
	check(Career.repair_cost({"broken_beams": 0, "deformed_beams": 0}) == 0.0, "A clean car costs nothing to repair")
	var bill := Career.repair_cost({"broken_beams": 40, "deformed_beams": 120, "radiator_damage": 0.6, "engine_damage": 0.2})
	print("  bill for a front-end crash: %s" % Career.money_text(bill))
	check(bill > 1000.0 and bill < 6000.0, "A front-end crash costs a plausible bill")
	check(Career.payout({"mode": 1, "medal": 3}) > Career.payout({"mode": 1, "medal": 0}), "A gold time trial pays more than a finish without medal")
	check(Career.payout({"mode": 4, "place": 1}) > Career.payout({"mode": 4, "place": 3}) and Career.payout({"mode": 4, "place": 4}) == 0.0, "Races pay by place, only the podium")
	check(Career.payout({"mode": 6, "escaped": false, "medal": 0}) == 0.0 and Career.payout({"mode": 6, "escaped": true, "medal": 3}) > 0.0, "An arrest pays nothing, an escape does")
	check(Career.money_text(12345.4) == "12.345 €" and Career.money_text(-80) == "-80 €", "Money is written the German way")
	# Account in an isolated profile.
	var path := "user://career_test_profile.json"
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var p := Progress.new()
	p.profile_path = path
	p.load_profile()
	check(is_equal_approx(p.get_money(), Career.START_MONEY), "A new career starts with %s" % Career.money_text(Career.START_MONEY))
	check(p.change_money(500.0) and is_equal_approx(p.get_money(), 2500.0), "Pay is credited")
	check(not p.change_money(-3000.0) and is_equal_approx(p.get_money(), 2500.0), "An overdraft is refused and changes nothing")
	check(p.change_money(-400.0), "A bill within the balance is paid")
	var again := Progress.new()
	again.profile_path = path
	again.load_profile()
	check(is_equal_approx(again.get_money(), 2100.0), "The balance survives a reload")
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	# In the game.
	var game := root.get_node("Game")
	game.progress.profile_path = "user://career_test_game.json"
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://career_test_game.json" + suffix))
	game.progress.load_profile()
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.settings["career"] = true
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
	var game := root.get_node("Game")
	game.settings["career"] = false
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://career_test_game.json" + suffix))
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true

func _press(scene: Node, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	scene._unhandled_input(ev)

func _run(scene: Node) -> void:
	var game := root.get_node("Game")
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	var start: float = game.progress.get_money()
	scene._on_activity_completed({"mode": 1, "medal": 2, "elapsed": 90.0})
	check(game.progress.get_money() > start, "A finished activity pays into the account")
	# Damage the car against a wall, then repair it on the spot.
	var car: SBVehicle = scene.player
	world.add_box(car.get_position_ws() + car.get_forward() * 30.0 + Vector3.UP, Vector3(1, 1, 4), Vector3.ZERO, 0.8)
	car.set_input(1, 0, 0, 0)
	world.step_blocking(5.0)
	world.sync_visuals()
	var bill := Career.repair_cost(car.get_telemetry())
	print("  bill after the wall: %s" % Career.money_text(bill))
	check(bill > 0.0, "Hitting a wall makes a repair bill")
	var before: float = game.progress.get_money()
	_press(scene, "repair_vehicle")
	world.step_blocking(0.2)
	world.sync_visuals()
	check(is_equal_approx(game.progress.get_money(), before - bill - Career.RECOVERY_FEE), "An instant repair charges towing plus the bill")
	check(Career.repair_cost(car.get_telemetry()) == 0.0, "and the car is repaired")
	# Broke: the repair is refused.
	car.reset_to(Transform3D(car.get_visual_basis(), car.get_position_ws()))
	world.step_blocking(0.5)
	car.set_input(1, 0, 0, 0)
	world.step_blocking(5.0)
	world.sync_visuals()
	game.progress.change_money(-game.progress.get_money())
	var damaged := Career.repair_cost(car.get_telemetry())
	_press(scene, "repair_vehicle")
	world.step_blocking(0.2)
	world.sync_visuals()
	check(damaged == 0.0 or Career.repair_cost(car.get_telemetry()) > 0.0, "With an empty account the instant repair is refused")
	# Fuel at the service: billed by the litre; an empty account stops the pump.
	game.progress.change_money(500.0)
	var eq = scene.equipment
	check(eq.recover_to_service(), "The car is towed to the service")
	world.step_blocking(1.0)
	world.sync_visuals()
	car.set_ignition(false)
	var fuel_before := float(car.get_telemetry()["fuel_l"])
	var money_before: float = game.progress.get_money()
	for i in 200:
		world.step_blocking(0.05)
		world.sync_visuals()
		eq.update_service(0.05, false, true)
	eq.update_service(0.05, false, false)   # nozzle back: settle the rest
	var litres := float(car.get_telemetry()["fuel_l"]) - fuel_before
	var paid := money_before - float(game.progress.get_money())
	print("  fuelled %.1f l, paid %s" % [litres, Career.money_text(paid)])
	check(litres > 1.0 and absf(paid - litres * Career.FUEL_PRICE) < 0.6 * Career.FUEL_PRICE + 0.01, "Fuel is billed by the litre")
	# Career off: free again (damage the car first, so a repair would cost something).
	car.set_input(1, 0, 0, 0)
	world.step_blocking(4.0)
	world.sync_visuals()
	game.settings["career"] = false
	var balance: float = game.progress.get_money()
	_press(scene, "repair_vehicle")
	world.step_blocking(0.2)
	world.sync_visuals()
	check(Career.repair_cost(car.get_telemetry()) == 0.0 and is_equal_approx(game.progress.get_money(), balance), "Outside the career repairs are free")
