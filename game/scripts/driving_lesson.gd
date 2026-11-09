extends Node
## Optional first-drive guide. Measures actual simulation snapshots, never drives the car.
const DriverPrompts := preload("res://scripts/driver_prompts.gd")

signal milestone_completed(id: String)
signal brake_result(distance: float, start_speed: float)
const MIN_BRAKE_SPEED := 50.0
var stage := "inactive"
var text := ""
var progress := 0.0
var status := ""
var brake_start_speed := 0.0
var brake_distance := 0.0
var brake_elapsed := 0.0
var game: Node
var _vehicle: SBVehicle
var _clock := -1.0
var _previous := Vector3.ZERO
var _previous_speed := 0.0
var _broken := 0
var _distance := 0.0
var _stopped_time := 0.0
var _suspended := false

func configure(scene: Node) -> void:
	game = scene
	var prompts := get_node_or_null("/root/Game/DriverPrompts")
	if prompts: prompts.device_changed.connect(_refresh)
	var equipment: Node = scene.get("equipment")
	if equipment and equipment.has_signal("service_completed"):
		equipment.connect("service_completed", _on_service_completed)
	_refresh()

func start() -> void:
	if not is_instance_valid(game): return
	var state := get_node_or_null("/root/Game")
	if state and str(state.get("selected_map")) != "proving_grounds":
		status = "Die Einführungsfahrt findet auf dem Testgelände statt."
		return
	stage = "ignition"
	status = "Fahre in deinem Tempo. Die Einführung greift nicht in die Steuerung ein."
	progress = 0
	_distance = 0
	brake_distance = 0
	brake_elapsed = 0
	brake_start_speed = 0
	_stopped_time = 0
	_clock = -1
	_vehicle = game.get("player")
	_suspended = false
	_refresh()

func reset() -> void:
	start()

func skip() -> void:
	stage = "skipped"
	status = "Einführung übersprungen · freie Fahrt"
	_refresh()

func visible_in_hud() -> bool:
	return stage not in ["inactive", "skipped"] and not _activity_selected()

func _activity_selected() -> bool:
	if not is_instance_valid(game): return false
	var activity: Node = game.get("activity")
	return activity != null and int(activity.get("mode")) != 0

func target() -> Vector3:
	if stage == "service" and is_instance_valid(game):
		var equipment: Node = game.get("equipment")
		if equipment != null: return equipment.get("bay")
	return Vector3.INF

func notify_interruption(reason: String) -> void:
	if stage in ["inactive", "skipped", "complete"]: return
	# A completed measurement remains earned; recovery may help reach the service bay.
	if stage == "service":
		_clock = -1
		status = "Bremsübung abgeschlossen · weiter zum Serviceplatz"
		return
	stage = "accelerate" if stage in ["accelerate", "brake", "service"] else "ignition"
	status = "Versuch neu beginnen: " + reason
	_distance = 0
	_stopped_time = 0
	brake_distance = 0
	brake_elapsed = 0
	brake_start_speed = 0
	_clock = -1
	_refresh()

func _process(_delta: float) -> void:
	if stage in ["inactive", "skipped", "complete"] or not is_instance_valid(game): return
	var world: SBWorld = game.get("world")
	var player: SBVehicle = game.get("player")
	if not is_instance_valid(world) or not is_instance_valid(player): return
	if _activity_selected():
		if not _suspended:
			notify_interruption("andere Aktivität gewählt")
		_suspended = true
		_clock = -1
		return
	_suspended = false
	if player != _vehicle:
		_vehicle = player
		notify_interruption("Fahrzeugwechsel")
	if world.paused: return
	_observe(float(world.get_stats()["sim_time"]), player.get_position_ws(), player.get_telemetry())

func _observe(now: float, position: Vector3, telemetry: Dictionary) -> void:
	var speed := absf(float(telemetry.get("speed_kmh", 0)))
	var broken := int(telemetry.get("broken_beams", 0))
	if _clock < 0:
		_anchor(now, position, speed, broken)
		return
	var dt := now - _clock
	if dt <= 0: return
	var travel := position.distance_to(_previous)
	# Long missing snapshots cannot produce a trustworthy braking distance.
	var max_travel := maxf(2.0, maxf(speed, _previous_speed) / 3.6 * dt * 1.6 + 0.5)
	if dt > 0.5 or travel > max_travel or broken < _broken:
		notify_interruption("Fahrzeug versetzt, repariert oder Messung unterbrochen")
		_anchor(now, position, speed, broken)
		return
	match stage:
		"ignition":
			if bool(telemetry.get("running", false)):
				stage = "drive"
				milestone_completed.emit("engine_started")
		"drive":
			if bool(telemetry.get("running", false)) and speed >= 5:
				_distance += travel
			if _distance >= 20 and speed >= 10:
				stage = "accelerate"
				milestone_completed.emit("first_drive")
		"accelerate":
			if broken > _broken:
				status = "Nutze eine freie Gerade für die Bremsmessung."
			elif _previous_speed >= MIN_BRAKE_SPEED and float(telemetry.get("brake", 0)) >= 0.2:
				stage = "brake"
				brake_start_speed = _previous_speed
				brake_distance = travel
				brake_elapsed = dt
				status = "Bremsmessung läuft. Bis zum Stillstand bremsen."
		"brake":
			if broken != _broken or float(telemetry.get("throttle", 0)) > 0.15 or speed > _previous_speed + 3 or (_previous_speed - speed) / dt > 90:
				notify_interruption("Kollision oder erneutes Beschleunigen")
			else:
				brake_distance += travel
				brake_elapsed += dt
				_stopped_time = _stopped_time + dt if speed < 1 else 0.0
				if _stopped_time >= 0.25 and brake_distance > 1:
					stage = "service"
					status = "%.0f → 0 km/h in %.1f m (%.1f s)." % [brake_start_speed, brake_distance, brake_elapsed]
					milestone_completed.emit("braking_exercise")
					brake_result.emit(brake_distance, brake_start_speed)
	_anchor(now, position, speed, broken)
	_refresh()

func _anchor(now: float, position: Vector3, speed: float, broken: int) -> void:
	_clock = now
	_previous = position
	_previous_speed = speed
	_broken = broken

func _on_service_completed(kind: String) -> void:
	if stage != "service" or kind != "refuel" or _activity_selected(): return
	if is_instance_valid(game):
		var world: SBWorld = game.get("world")
		if world != null and world.paused: return
	stage = "complete"
	status = "Erste Fahrt, Bremsübung und Tankstopp abgeschlossen. Freie Fahrt!"
	milestone_completed.emit("first_service")
	milestone_completed.emit("first_drive_complete")
	_refresh()

func _refresh() -> void:
	match stage:
		"ignition":
			text = "1 / 4 · %s Motor starten. Läuft er bereits, mit %s losfahren." % [DriverPrompts.hint("ignition"), DriverPrompts.hint("throttle")]
			progress = 0
		"drive":
			text = "1 / 4 · Fahre 20 m: %s Gas, %s Bremse, %s lenken." % [DriverPrompts.hint("throttle"), DriverPrompts.hint("brake"), DriverPrompts.hint("steering")]
			progress = clampf(_distance / 20, 0, 1) * 0.25
		"accelerate":
			text = "2 / 4 · Freie Gerade: mindestens 50 km/h erreichen, dann mit %s bremsen." % DriverPrompts.hint("brake")
			progress = 0.25
		"brake":
			text = "2 / 4 · Bremse bis zum Stillstand · %.1f m seit Bremsbeginn" % brake_distance
			progress = 0.25 + clampf(1.0 - _previous_speed / maxf(brake_start_speed, 1), 0, 1) * 0.25
		"service":
			text = "3 / 4 · Zum Serviceplatz fahren, anhalten, %s Motor aus. %s zum Tanken halten." % [DriverPrompts.hint("ignition"), DriverPrompts.hint("refuel")]
			progress = 0.75
		"complete":
			text = "4 / 4 · Einführung geschafft · F3 für Zeitfahren oder Drift-Challenge"
			progress = 1
		_:
			text = ""
