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
	return {"version": VERSION, "milestones": {}, "braking": {}, "selection": {"last_car": "", "last_map": ""},
		"career": {"money": 2000.0, "earned": 0.0, "spent": 0.0}}

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not _number(data.get("version")) or float(data["version"]) != VERSION: return false
	if not data.get("milestones") is Dictionary or not data.get("braking") is Dictionary or not data.get("selection") is Dictionary: return false
	for value in data["milestones"].values():
		if not value is bool: return false
	# Career section (added later): optional, but when present it must hold finite numbers.
	if data.has("career"):
		var career: Variant = data["career"]
		if not career is Dictionary: return false
		for key in ["money", "earned", "spent"]:
			if not _number(career.get(key, 0.0)): return false
		if career.has("contracts"):
			if not career["contracts"] is Dictionary: return false
			for c in career["contracts"].values():
				if not c is Dictionary: return false
				for key in ["mode", "medal", "bonus", "serial"]:
					if not _number(c.get(key, 0)): return false
		if career.has("owned"):
			if not career["owned"] is Array: return false
			for id in career["owned"]:
				if not id is String: return false
	if data.has("paint"):
		if not data["paint"] is Dictionary: return false
		for rgb in data["paint"].values():
			if not rgb is Array or rgb.size() != 3: return false
			for c in rgb:
				if not _number(c): return false
	if data.has("configs"):
		if not data["configs"] is Dictionary: return false
		for cfg in data["configs"].values():
			if not cfg is Dictionary: return false
			for v in cfg.values():
				if not (v is String or _number(v)): return false
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

## Paint chosen for a car (car id from the car file), or null for the factory colour.
func get_paint(car_id: String) -> Variant:
	var rgb: Variant = (_data.get("paint", {}) as Dictionary).get(car_id)
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2])) if rgb is Array else null

## Store a paint colour for a car; null goes back to the factory colour.
func set_paint(car_id: String, color: Variant) -> bool:
	if read_only: return false
	var previous := _data.duplicate(true)
	var all: Dictionary = (_data.get("paint", {}) as Dictionary).duplicate()
	if color is Color: all[car_id] = [color.r, color.g, color.b]
	else: all.erase(car_id)
	_data["paint"] = all
	return _commit(previous)

## Werkstatt configuration of a car (vehicle_workshop.gd), {} for the factory build.
func get_config(car_id: String) -> Dictionary:
	var cfg: Variant = (_data.get("configs", {}) as Dictionary).get(car_id)
	return (cfg as Dictionary).duplicate() if cfg is Dictionary else {}

func set_config(car_id: String, cfg: Dictionary) -> bool:
	if read_only: return false
	var previous := _data.duplicate(true)
	var all: Dictionary = (_data.get("configs", {}) as Dictionary).duplicate(true)
	if cfg.is_empty(): all.erase(car_id)
	else: all[car_id] = cfg.duplicate()
	_data["configs"] = all
	return _commit(previous)

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


# ------------------------------------------------------------------------------- career
func _career() -> Dictionary:
	if not _data.has("career"):
		_data["career"] = {"money": 2000.0, "earned": 0.0, "spent": 0.0}
	return _data["career"]

func get_money() -> float:
	return float(_career().get("money", 0.0))

## Credit (positive) or debit (negative) the career balance. A debit larger than the balance is
## refused and changes nothing; so is any change while the profile cannot be saved.
func change_money(amount: float) -> bool:
	if read_only or not is_finite(amount): return false
	var career := _career()
	var money := float(career.get("money", 0.0))
	if amount < 0.0 and money + amount < -0.005: return false
	var previous := _data.duplicate(true)
	career["money"] = money + amount
	if amount > 0.0: career["earned"] = float(career.get("earned", 0.0)) + amount
	else: career["spent"] = float(career.get("spent", 0.0)) - amount
	return _commit(previous)

func owns_car(car_id: String) -> bool:
	return car_id in (_career().get("owned", []) as Array)

func owned_cars() -> Array:
	return (_career().get("owned", []) as Array).duplicate()

## Buy a car: the price is debited and the car added in one save, or nothing changes (not enough
## money, already owned, or the profile cannot be saved).
func buy_car(car_id: String, price: float) -> bool:
	if read_only or car_id.is_empty() or owns_car(car_id) or not is_finite(price) or price < 0.0: return false
	var career := _career()
	var money := float(career.get("money", 0.0))
	if money - price < -0.005: return false
	var previous := _data.duplicate(true)
	career["money"] = money - price
	career["spent"] = float(career.get("spent", 0.0)) + price
	var owned: Array = career.get("owned", []).duplicate()
	owned.append(car_id)
	career["owned"] = owned
	return _commit(previous)

## The map's open contract ({} if none issued yet).
func get_contract(map_id: String) -> Dictionary:
	var c: Dictionary = (_career().get("contracts", {}) as Dictionary).get(map_id, {})
	if c.is_empty(): return {}
	# JSON keeps every number as a float: hand out the integer fields as integers again.
	return {"mode": int(c.get("mode", 0)), "medal": int(c.get("medal", 1)), "bonus": float(c.get("bonus", 0.0)), "serial": int(c.get("serial", 0))}

func contracts_done() -> int:
	return int(_career().get("contracts_done", 0))

func set_contract(map_id: String, contract: Dictionary) -> bool:
	if read_only: return false
	var previous := _data.duplicate(true)
	var all: Dictionary = (_career().get("contracts", {}) as Dictionary).duplicate(true)
	all[map_id] = contract.duplicate()
	_career()["contracts"] = all
	return _commit(previous)

## Pay a fulfilled contract's bonus, count it and put the next contract up, in one save.
func complete_contract(map_id: String, bonus: float, next: Dictionary) -> bool:
	if read_only or not is_finite(bonus) or bonus < 0.0: return false
	var previous := _data.duplicate(true)
	var career := _career()
	career["money"] = float(career.get("money", 0.0)) + bonus
	career["earned"] = float(career.get("earned", 0.0)) + bonus
	career["contracts_done"] = int(career.get("contracts_done", 0)) + 1
	var all: Dictionary = (career.get("contracts", {}) as Dictionary).duplicate(true)
	all[map_id] = next.duplicate()
	career["contracts"] = all
	return _commit(previous)

func reset_career() -> bool:
	if read_only: return false
	var previous := _data.duplicate(true)
	_data["career"] = {"money": 2000.0, "earned": 0.0, "spent": 0.0}
	return _commit(previous)
