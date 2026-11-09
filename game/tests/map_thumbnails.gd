extends SceneTree
## Renders the menu thumbnails of every map: godot -s res://tests/map_thumbnails.gd [-- <map_id> ...]
## Output: res://ui/maps/<id>.png (elevated view along the route, 480x270).
var maps: Array = []
var frame := 0
var wait := 0
var cam: Camera3D
var current := ""
const VIEW := {  # route fraction, height, distance behind
	"proving_grounds": [0.62, 18.0, 46.0], "autobahn": [0.12, 16.0, 40.0], "city": [0.30, 22.0, 30.0],
	"desert": [0.08, 26.0, 40.0], "hill_roads": [0.22, 12.0, 30.0], "offroad": [0.35, 10.0, 26.0],
}

func _initialize() -> void:
	call_deferred("_next")

func _next() -> void:
	if frame == 0:
		var args := OS.get_cmdline_user_args()
		for m in root.get_node("Game").MAPS:
			if args.is_empty() or m["id"] in args:
				maps.append(m["id"])
	frame += 1
	if maps.is_empty():
		quit()
		return
	current = maps.pop_front()
	var game := root.get_node("Game")
	game.selected_map = current
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	wait = 0

func _process(_d: float) -> bool:
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return false
	wait += 1
	if wait == 3:
		scene.world.time_scale = 0.0
		scene.hud.visible = false
		scene.minimap.visible = false
		var wps: Array = scene.map_data.get("waypoints", [])
		var v: Array = VIEW.get(current, [0.3, 14.0, 32.0])
		var n := wps.size()
		var i := int(v[0] * n) % maxi(n, 1)
		var a: Vector3 = wps[i] if n > 0 else Vector3.ZERO
		var b: Vector3 = wps[(i + 6) % n] if n > 0 else Vector3(1, 0, 0)
		var dir := b - a
		dir.y = 0
		dir = dir.normalized()
		cam = Camera3D.new()
		cam.fov = 58
		cam.far = 4000
		scene.add_child(cam)
		cam.current = true
		cam.look_at_from_position(a - dir * float(v[2]) + Vector3.UP * float(v[1]) + dir.cross(Vector3.UP) * 8.0, a + dir * 60.0, Vector3.UP)
	if wait == 14:
		var img := root.get_viewport().get_texture().get_image()
		img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path("res://ui/maps/%s.png" % current))
		print("map thumbnail ", current)
		call_deferred("_next")
		wait = -1000
	return false
