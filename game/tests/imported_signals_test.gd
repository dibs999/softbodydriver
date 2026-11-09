extends SceneTree
var failed := false
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state := root.get_node("Game")
	state.settings["traffic"] = false
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/concept_gt.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var game = current_scene
	game.set_process(false)
	game.world.paused = true
	var equipment = game.equipment
	var lamps: Dictionary = equipment.state_for(game.player)
	check(not lamps["authored_signals"].is_empty(), "Concept uses its imported skinned rear signal lenses")
	check(lamps["left"].size() == 1 and lamps["right"].size() == 1, "No duplicate generated rear signal boxes")
	var event := InputEventAction.new()
	event.action = "indicator_left"
	event.pressed = true
	equipment.handle_action(event)
	equipment.clock = 0.1
	equipment._process(0)
	for material in lamps["authored_signals"]:
		check(material.get_shader_parameter("left_on") and not material.get_shader_parameter("right_on"), "Imported lens shader lights only requested side")
	equipment.clock = 0.6
	equipment._process(0)
	for material in lamps["authored_signals"]:
		check(not material.get_shader_parameter("left_on") and not material.get_shader_parameter("right_on"), "Imported signal lenses follow blink off phase")
	print("IMPORTED SIGNALS TEST ", "OK" if not failed else "FAILED")
	quit(1 if failed else 0)
