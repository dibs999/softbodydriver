extends SceneTree
## Activity medals: timed runs against the map's AI reference pace, races by place, the crash test
## by stars; the best medal per map and mode is kept, and the menu tally counts them.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	var Activity := preload("res://scripts/driving_activity.gd")
	var path := "user://medals_test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var a = Activity.new()
	a.records_path = path
	root.add_child(a)
	# A straight 1 km route at a uniform 20 m/s AI pace: reference time 50 s.
	var wps := PackedVector3Array()
	var speeds := PackedFloat32Array()
	for i in 101:
		wps.append(Vector3(i * 10.0, 0, 0))
		speeds.append(20.0)
	a.configure("test_map", {"spawns": [Transform3D.IDENTITY], "waypoints": wps, "speeds": speeds})
	a.route = PackedVector3Array([Vector3.ZERO, Vector3(1000, 0, 0)])
	check(absf(a.reference_time(a.route, 1) - 50.0) < 0.01, "Reference time is the route at the AI's mean pace (%.1f s)" % a.reference_time(a.route, 1))
	check(a.medal_for(1, {"elapsed": 49.0}) == 3, "At the reference pace: gold")
	check(a.medal_for(1, {"elapsed": 58.0}) == 2, "Within 20 %: silver")
	check(a.medal_for(1, {"elapsed": 72.0}) == 1, "Within 50 %: bronze")
	check(a.medal_for(1, {"elapsed": 80.0}) == 0, "Slower: no medal")
	check(a.medal_for(4, {"place": 1, "field": 3}) == 3 and a.medal_for(4, {"place": 2, "field": 3}) == 2, "Race: first gold, second silver")
	check(a.medal_for(4, {"place": 3, "field": 3}) == 0, "Race: last of three gets nothing")
	check(a.medal_for(5, {"crash": {"stars": 5}}) == 3 and a.medal_for(5, {"crash": {"stars": 3}}) == 1 and a.medal_for(5, {"crash": {"stars": 2}}) == 0, "Crash test: by stars")
	check(a.medal_for(2, {"score": 99999}) == 0, "Drift challenge: no medals")
	# Saving keeps the best medal and the tally counts it.
	a._records.set_value("medals", "test_map:1", 2)
	a._records.set_value("medals", "other_map:4", 3)
	a._records.save(path)
	var tally: Array[int] = Activity.medal_tally(path)
	check(tally == [0, 1, 1], "Tally counts one silver and one gold (%s)" % str(tally))
	check(a.best_medal("test_map", 1) == 2, "Best medal per map and mode is stored")
	a.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MEDALS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
