extends RefCounted
## Versioned player progress. JSON fields not owned here survive load/save.
## A future version or unrecoverable corrupt profile is read-only, never reset implicitly.
const VERSION := 1
var profile_path := "user://player_progress.json"
var last_error: Error = OK
var recovered_backup := false
var read_only := false
var _data: Dictionary = _defaults()

static func _defaults() -> Dictionary:
	return {"version": VERSION, "milestones": {}, "braking": {}, "selection": {"last_car": "", "last_map": ""}}

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not _number(data.get("version")) or float(data["version"]) != VERSION: return false
	if not data.get("milestones") is Dictionary or not data.get("braking") is Dictionary or not data.get("selection") is Dictionary: return false
	for value in data["milestones"].values():
		if not value is bool: return false
	var selection: Dictionary = data["selection"]
	if not selection.get("last_car") is String or not selection.get("last_map") is String: return false
	for car in data["braking"].values():
		if not car is Dictionary or not car.get("buckets") is Dictionary or not car.get("selected_bucket") is String: return false
		if not car["buckets"].has(car["selected_bucket"]): return false
		for record in car["buckets"].values():
			if not record is Dictionary: return false
			if not _number(record.get("distance_m")) or float(record["distance_m"]) <= 0: return false
			if not _number(record.get("start_speed_kmh")) or float(record["start_speed_kmh"]) < 10: return false
	return true

func _read(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	# Profiles are tiny; reject huge or truncated files without exhausting memory.
	if file.get_length() > 1048576: return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return null
	return parser.data

func load_profile() -> Error:
	_data = _defaults()
	read_only = false
	recovered_backup = false
	last_error = OK
	if not FileAccess.file_exists(profile_path):
		if not FileAccess.file_exists(profile_path + ".bak"): return OK
	else:
		var candidate: Variant = _read(profile_path)
		# Do not roll a newer profile back to an older backup.
		if candidate is Dictionary and _number(candidate.get("version")) and float(candidate["version"]) != VERSION:
			read_only = true
			last_error = ERR_UNAVAILABLE
			return last_error
		if _valid(candidate):
			_data = candidate
			return OK
	var backup: Variant = _read(profile_path + ".bak")
	if _valid(backup):
		_data = backup
		recovered_backup = true
		return OK
	read_only = true
	last_error = ERR_FILE_CORRUPT
	return last_error

func save_profile() -> Error:
	if read_only:
		if last_error == OK: last_error = ERR_UNAVAILABLE
		return last_error
	if not _valid(_data):
		last_error = ERR_INVALID_DATA
		return last_error
	var path := ProjectSettings.globalize_path(profile_path)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(_data, "\t"))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error != OK: return last_error
	# Verify the complete new file before touching the last good profile.
	if not _valid(_read(temp)):
		last_error = ERR_FILE_CORRUPT
		return last_error
	# Only a valid primary may replace the backup; preserve it after recovery.
	if _valid(_read(profile_path)):
		last_error = DirAccess.copy_absolute(path, path + ".bak.tmp")
		if last_error != OK: return last_error
		last_error = DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak")
		if last_error != OK: return last_error
	# Same-directory rename replaces the primary atomically on the supported Linux runtime.
	last_error = DirAccess.rename_absolute(temp, path)
	if last_error == OK: recovered_backup = false
	return last_error

func _commit(previous: Dictionary) -> bool:
	if save_profile() == OK: return true
	_data = previous
	return false

func complete_milestone(id: String) -> bool:
	if id.is_empty() or read_only: return false
	if is_completed(id): return true
	var previous := _data.duplicate(true)
	_data["milestones"][id] = true
	return _commit(previous)

func is_completed(id: String) -> bool:
	return _data["milestones"].get(id, false)

func completed_count() -> int:
	var count := 0
	for complete in _data["milestones"].values():
		if complete: count += 1
	return count

func record_braking(car_id: String, distance_m: float, start_speed_kmh: float) -> bool:
	if read_only or car_id.is_empty() or not is_finite(distance_m) or distance_m <= 0 or not is_finite(start_speed_kmh) or start_speed_kmh < 10: return false
	# Do not compare a 30 km/h stop with a 100 km/h stop. Store exact start speed too.
	var bucket := str(roundi(start_speed_kmh / 10.0) * 10)
	var car: Dictionary = _data["braking"].get(car_id, {"buckets": {}, "selected_bucket": bucket})
	var old: Dictionary = car["buckets"].get(bucket, {})
	if not old.is_empty() and distance_m >= float(old["distance_m"]): return false
	var previous := _data.duplicate(true)
	var record := old.duplicate(true)
	record["distance_m"] = distance_m
	record["start_speed_kmh"] = start_speed_kmh
	car["buckets"][bucket] = record
	car["selected_bucket"] = bucket
	_data["braking"][car_id] = car
	return _commit(previous)

func get_best_braking(car_id: String) -> Dictionary:
	var car: Dictionary = _data["braking"].get(car_id, {})
	if car.is_empty(): return {}
	return car["buckets"][car["selected_bucket"]].duplicate(true)

func set_selection(car_path: String, map_id: String) -> bool:
	if read_only or car_path.is_empty() or map_id.is_empty(): return false
	var previous := _data.duplicate(true)
	_data["selection"]["last_car"] = car_path
	_data["selection"]["last_map"] = map_id
	return _commit(previous)

func get_selection() -> Dictionary:
	return _data["selection"].duplicate(true)

func reset_lesson() -> bool:
	if read_only: return false
	var previous := _data.duplicate(true)
	_data["milestones"] = {}
	return _commit(previous)
