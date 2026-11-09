extends SceneTree
const Progress := preload("res://scripts/player_progress.gd")
var failures := 0
var directory := ""
var path := ""

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func write(value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func read() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func fresh():
	var profile := Progress.new()
	profile.profile_path = path
	return profile

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	directory = "/tmp/softbody-progress-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Isolated test directory created")
	path = directory + "/profile.json"
	var profile = fresh()
	check(profile.load_profile() == OK and profile.completed_count() == 0, "Missing profile starts empty without a file")
	check(not FileAccess.file_exists(path), "Loading defaults does not write automatically")
	check(profile.complete_milestone("start_engine"), "Milestone saved")
	check(profile.set_selection("res://cars/concept_gt.car.json", "proving_grounds"), "Last selection saved")
	check(profile.record_braking("concept_gt", 25.0, 50.0), "First stopping result saved with speed")
	check(not profile.record_braking("concept_gt", 26.0, 50.0), "Worse same-speed result cannot replace best")
	check(profile.record_braking("concept_gt", 24.0, 50.0), "Better same-speed result replaces best")
	check(profile.record_braking("concept_gt", 45.0, 100.0), "Different speed retains separate comparable result")
	check(not profile.record_braking("concept_gt", 25.0, 50.0), "Earlier speed bucket survives later result")
	check(not profile.record_braking("concept_gt", NAN, 50.0) and not profile.record_braking("concept_gt", 1, INF) and not profile.record_braking("concept_gt", -1, 50), "Invalid numeric records rejected")
	var loaded = fresh()
	check(loaded.load_profile() == OK and loaded.is_completed("start_engine"), "Milestone survives save/reload")
	check(loaded.get_selection()["last_map"] == "proving_grounds", "Selection survives reload")
	var best: Dictionary = loaded.get_best_braking("concept_gt")
	check(best["distance_m"] == 45 and best["start_speed_kmh"] == 100, "Exact stopping context survives reload")
	best["distance_m"] = 0
	check(loaded.get_best_braking("concept_gt")["distance_m"] == 45, "Getter cannot mutate stored result")
	var data := read()
	data["extension"] = {"future": [1, 2, "keep"]}
	data["selection"]["camera"] = "cockpit"
	data["braking"]["concept_gt"]["buckets"]["100"]["conditions"] = "dry"
	write(data)
	check(loaded.load_profile() == OK and loaded.complete_milestone("braking"), "Extended valid profile remains editable")
	data = read()
	check(data["extension"]["future"][2] == "keep" and data["selection"]["camera"] == "cockpit", "Unknown top-level and nested fields preserved")
	check(loaded.record_braking("concept_gt", 43, 100), "Improvement on extended record saved")
	check(read()["braking"]["concept_gt"]["buckets"]["100"]["conditions"] == "dry", "Unknown record fields preserved on improvement")
	check(loaded.reset_lesson() and loaded.completed_count() == 0, "Tutorial resets only by explicit request")
	check(loaded.get_best_braking("concept_gt")["distance_m"] == 43 and loaded.get_selection()["last_map"] == "proving_grounds", "Tutorial reset keeps records and selection")
	var backup_text := FileAccess.get_file_as_string(path + ".bak")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	var recovered = fresh()
	check(recovered.load_profile() == OK and recovered.recovered_backup, "Corrupt primary recovers validated backup")
	check(recovered.complete_milestone("recovered"), "Recovered profile can save again")
	check(FileAccess.get_file_as_string(path + ".bak") == backup_text, "Corrupt primary never replaces valid backup")
	data = read()
	data["version"] = 2
	write(data)
	var future_text := FileAccess.get_file_as_string(path)
	var future = fresh()
	check(future.load_profile() == ERR_UNAVAILABLE and future.read_only, "Future schema is protected despite older backup")
	check(not future.complete_milestone("bad") and future.save_profile() != OK, "Future profile cannot be overwritten")
	check(FileAccess.get_file_as_string(path) == future_text, "Future file untouched")
	DirAccess.remove_absolute(path + ".bak")
	data["version"] = 1
	data["milestones"] = {"start_engine": "true"}
	write(data)
	var malformed = fresh()
	check(malformed.load_profile() == ERR_FILE_CORRUPT and malformed.read_only, "Malformed field type rejected without implicit reset")
	check(not malformed.reset_lesson(), "Tutorial reset cannot erase corrupt profile")
	# I/O errors must roll back the in-memory state too.
	var unwritable = Progress.new()
	unwritable.profile_path = directory + "/missing/profile.json"
	check(not unwritable.complete_milestone("unsaved") and not unwritable.is_completed("unsaved"), "Failed save does not pretend progress is persisted")
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("PLAYER PROGRESS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
