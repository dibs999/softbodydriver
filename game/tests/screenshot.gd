extends SceneTree
## Renders screenshots of a scene: godot -s res://tests/screenshot.gd -- <scene> <out_prefix> [car] [map] [frames...]

var frames_to_shoot: Array = []
var frame := 0
var prefix := "user://shot"
var actions: Array = []

var scene_path := ""

func _initialize() -> void:
	pass

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := args[0] if args.size() > 0 else "res://scenes/game.tscn"
	prefix = args[1] if args.size() > 1 else "/tmp/shot"
	var game := root.get_node("Game")
	if args.size() > 2 and args[2] != "-":
		game.selected_car = args[2]
	if args.size() > 3 and args[3] != "-":
		game.selected_map = args[3]
	game.settings["show_help"] = false
	for i in range(4, args.size()):
		frames_to_shoot.append(int(args[i]))
	if frames_to_shoot.is_empty():
		frames_to_shoot = [120]
	change_scene_to_file(scene)

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
		return false
	var cs := current_scene
	if cs and cs.has_method("_drive_player") and cs.get("player"):
		# Scripted driving: accelerate, steer a bit, then hit the wall lane.
		var p = cs.player
		if frame > 30:
			Input.action_press("throttle", 1.0)
	if frame in frames_to_shoot:
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s_%04d.png" % [prefix, frame]
		img.save_png(path)
		print("saved ", path)
	if frame >= frames_to_shoot.max() + 1:
		return true
	return false
