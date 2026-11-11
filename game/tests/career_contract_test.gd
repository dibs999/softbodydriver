extends SceneTree
## Career contracts: every map offers one activity with a minimum medal and a bonus; finishing it
## with that medal pays the bonus on top of the normal pay, counts it and puts up the next one.
## godot --headless -s res://tests/career_contract_test.gd
const Career := preload("res://scripts/career.gd")
const Progress := preload("res://scripts/player_progress.gd")
const PROFILE := "user://career_contract_test.json"
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _clean(path: String) -> void:
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _initialize() -> void:
	# Rules.
	var a := Career.make_contract("city", [0, 1, 2, 3], 0, 0)
	var again := Career.make_contract("city", [0, 1, 2, 3], 0, 0)
	var b := Career.make_contract("city", [0, 1, 2, 3], 1, 1)
	print("  contract: " + Career.contract_text(a))
	check(a == again and int(a["mode"]) in [1, 2, 3], "A contract is reproducible and never free driving")
	check(int(a["medal"]) <= 2 and float(a["bonus"]) > 0.0, "Early contracts ask for bronze or silver and pay a bonus")
	check(a != b, "The next contract differs")
	check(Career.make_contract("x", [0], 0, 0).is_empty(), "A map with only free driving has no contract")
	check(Career.fulfils(a, {"mode": a["mode"], "medal": a["medal"]}) and not Career.fulfils(a, {"mode": a["mode"], "medal": int(a["medal"]) - 1}), "The medal must be reached")
	check(not Career.fulfils(a, {"mode": int(a["mode"]) % 3 + 1, "medal": 3}) or int(a["mode"]) % 3 + 1 == int(a["mode"]), "Another activity does not count")
	var late := Career.make_contract("city", [1], 5, 10)
	check(float(late["bonus"]) > float(Career.make_contract("city", [1], 5, 0)["bonus"]) * 1.5, "Bonuses grow with the contracts done")
	# Profile.
	_clean("user://career_contract_unit.json")
	var p := Progress.new()
	p.profile_path = "user://career_contract_unit.json"
	p.load_profile()
	check(p.get_contract("city").is_empty() and p.contracts_done() == 0, "A new career has no contracts yet")
	check(p.set_contract("city", a) and p.get_contract("city") == a, "A contract is stored per map")
	var money := p.get_money()
	check(p.complete_contract("city", float(a["bonus"]), b) and is_equal_approx(p.get_money(), money + float(a["bonus"])) and p.contracts_done() == 1 and p.get_contract("city") == b, "Completing pays, counts and puts up the next")
	var reload := Progress.new()
	reload.profile_path = "user://career_contract_unit.json"
	reload.load_profile()
	check(reload.get_contract("city") == b and reload.contracts_done() == 1, "Contracts survive a reload")
	_clean("user://career_contract_unit.json")
	# In the game.
	var game := root.get_node("Game")
	_clean(PROFILE)
	game.progress.profile_path = PROFILE
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
		if frame > 600: check(false, "game never loaded")
		return frame > 600 and _finish()
	if frame < 5: return false
	var game := root.get_node("Game")
	var c: Dictionary = game.progress.get_contract("proving_grounds")
	print("  proving ground contract: " + Career.contract_text(c))
	check(not c.is_empty() and int(c["mode"]) in scene.activity.available_modes(), "Entering a map puts up a contract it can offer")
	var money: float = game.progress.get_money()
	var result := {"mode": int(c["mode"]), "medal": 3, "score": 6000.0, "elapsed": 60.0, "checkpoints": 4, "place": 1, "field": 4, "escaped": true, "crash": {"stars": 5}}
	scene._on_activity_completed(result)
	var expected := money + Career.payout(result) + float(c["bonus"])
	var next: Dictionary = game.progress.get_contract("proving_grounds")
	print("  paid %s, next: %s" % [Career.money_text(game.progress.get_money() - money), Career.contract_text(next)])
	check(is_equal_approx(game.progress.get_money(), expected), "A fulfilled contract pays its bonus on top of the pay")
	check(game.progress.contracts_done() == 1 and int(next["serial"]) == int(c["serial"]) + 1, "and the next contract goes up")
	var before: float = game.progress.get_money()
	scene._on_activity_completed({"mode": int(next["mode"]), "medal": 0, "elapsed": 999.0})
	check(game.progress.contracts_done() == 1 and is_equal_approx(game.progress.get_money(), before + Career.payout({"mode": int(next["mode"]), "medal": 0, "elapsed": 999.0})), "Without the medal the contract stays open")
	return _finish()

func _finish() -> bool:
	root.get_node("Game").settings["career"] = false
	_clean(PROFILE)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
