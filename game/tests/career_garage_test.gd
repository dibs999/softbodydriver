extends SceneTree
## Career garage: cars have dealer prices that grow with the power, a purchase debits the account
## and is saved, the menu turns the start button into a buy button for a car the career does not
## own, and the game never spawns an unowned car with the career on.
## godot --headless -s res://tests/career_garage_test.gd
const Career := preload("res://scripts/career.gd")
const Progress := preload("res://scripts/player_progress.gd")
const PROFILE := "user://career_garage_test.json"
var frame := 0
var failed := false
var stage := 0

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _clean(path: String) -> void:
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _initialize() -> void:
	var game := root.get_node("Game")
	if game.cars.is_empty(): game.scan_cars()   # the autoload is not ready yet in _initialize
	# Prices.
	var hatch: Dictionary = game.car_info("res://cars/kestrel_hatch.car.json")
	var sedan: Dictionary = game.car_info("res://cars/meridian_sedan.car.json")
	var gt: Dictionary = game.car_info("res://cars/concept_gt.car.json")
	print("  prices: Meridian %s, Concept GT %s" % [Career.money_text(Career.car_price(sedan)), Career.money_text(Career.car_price(gt))])
	check(Career.car_price(sedan) > Career.START_MONEY and Career.car_price(sedan) < 8000.0, "The next car is a few activities away")
	check(Career.car_price(gt) > 3.0 * Career.car_price(sedan), "The supercar costs a lot more")
	check(fmod(Career.car_price(gt), 250.0) == 0.0, "Prices are round")
	# Buying in an isolated profile.
	_clean("user://career_garage_unit.json")
	var p := Progress.new()
	p.profile_path = "user://career_garage_unit.json"
	p.load_profile()
	check(Career.owns(p, str(hatch["id"])) and not Career.owns(p, str(sedan["id"])), "A new career owns only the starter car")
	check(not p.buy_car(str(sedan["id"]), 1.0e6) and not p.owns_car(str(sedan["id"])) and is_equal_approx(p.get_money(), Career.START_MONEY), "A car beyond the balance is not sold")
	p.change_money(5000.0)
	var before := p.get_money()
	check(p.buy_car(str(sedan["id"]), 4000.0) and p.owns_car(str(sedan["id"])) and is_equal_approx(p.get_money(), before - 4000.0), "A purchase debits the price and adds the car")
	check(not p.buy_car(str(sedan["id"]), 10.0) and is_equal_approx(p.get_money(), before - 4000.0), "An owned car is not bought twice")
	var again := Progress.new()
	again.profile_path = "user://career_garage_unit.json"
	again.load_profile()
	check(again.owns_car(str(sedan["id"])) and is_equal_approx(again.get_money(), before - 4000.0), "The garage survives a reload")
	again.reset_career()
	check(not again.owns_car(str(sedan["id"])), "A new career starts with an empty garage")
	_clean("user://career_garage_unit.json")
	# The menu with the career on.
	_clean(PROFILE)
	game.progress.profile_path = PROFILE
	game.progress.load_profile()
	game.settings["career"] = true
	game.settings["traffic"] = false
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.selected_map = "proving_grounds"   # open from the start of a career
	change_scene_to_file("res://scenes/main_menu.tscn")

func _menu(scene: Node) -> void:
	var game := root.get_node("Game")
	var sedan: Dictionary = game.car_info("res://cars/meridian_sedan.car.json")
	var price := Career.car_price(sedan)
	var button: Button = scene.start_button
	print("  start button: '%s' disabled %s" % [button.text, button.disabled])
	check(button.text.begins_with("Kaufen") and button.disabled, "An unowned car beyond the balance cannot be bought")
	game.progress.change_money(price + 100.0 - game.progress.get_money())
	scene._refresh_garage()
	check(not button.disabled, "With enough money the buy button is enabled")
	var tree_scene := current_scene
	scene._on_start()
	check(current_scene == tree_scene and game.progress.owns_car(str(sedan["id"])) and is_equal_approx(game.progress.get_money(), 100.0), "The first press buys the car and stays in the menu")
	check(button.text.begins_with("Losfahren"), "then the button drives it")
	var idx := -1
	for i in game.cars.size():
		if game.cars[i]["path"] == "res://cars/meridian_sedan.car.json": idx = i
	check(idx >= 0 and scene.car_meta[idx].text.ends_with("im Besitz"), "The tile shows the car as owned")
	# The game falls back to the starter car for a car the career does not own.
	game.selected_car = "res://cars/concept_gt.car.json"
	game.selected_map = "proving_grounds"
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if stage == 0:
		if scene == null or not scene.get("start_button") or frame < 5:
			return frame > 600 and _finish("menu never loaded")
		_menu(scene)
		stage = 1
		frame = 0
		return false
	if scene == null or not scene.get("player") or frame < 5:
		return frame > 600 and _finish("game never loaded")
	var player: SBVehicle = scene.player
	print("  spawned: %s" % player.get_info().get("id", "?"))
	check(str(player.get_info().get("id", "")) == Career.STARTER_CAR, "An unowned car is never spawned in the career")
	return _finish("")

func _finish(error: String) -> bool:
	if not error.is_empty(): check(false, error)
	var game := root.get_node("Game")
	game.settings["career"] = false
	_clean(PROFILE)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
