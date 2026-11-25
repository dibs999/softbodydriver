extends SceneTree
## Ambient birds are spawned for every driving map, start above the ground and move on finite paths.
## godot --headless -s res://tests/ambient_life_test.gd
const AmbientLife := preload("res://scripts/ambient_life.gd")
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for map_id in ["city", "autobahn", "offroad", "hill_roads", "desert", "proving_grounds"]:
		var life := AmbientLife.new()
		root.add_child(life)
		life.configure(map_id)
		check(life.get_child_count() >= 4, "%s has an ambient flock" % map_id)
		life._process(0.2)
		var before: Vector3 = (life.get_child(0) as Node3D).position
		life._process(0.2)
		var after: Vector3 = (life.get_child(0) as Node3D).position
		check(after.is_finite() and after.y > 25.0 and after.distance_to(before) < 20.0, "%s birds move on a bounded high path" % map_id)
		life.queue_free()
	print("AMBIENT LIFE TEST ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
