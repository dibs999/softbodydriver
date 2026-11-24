extends Node
## Freeroam jump measurement. The physics-agnostic `observe` state machine is unit-testable;
## `_process` only feeds it telemetry and turns valid landings into persistent map records.

var player: SBVehicle
var world: SBWorld
var hud: Control
var map_id := ""

var _clock := -1.0
var _airborne := false
var _grounded := 0.0
var _start_time := 0.0
var _start_pos := Vector3.ZERO
var _last_pos := Vector3.INF
var _cooldown := 0.0

const MIN_SPEED_KMH := 25.0
const MIN_AIRTIME := 0.35
const MIN_DISTANCE := 7.0
const MAX_JUMP_TIME := 5.0
const TELEPORT_DISTANCE := 30.0

func configure(id: String, player_vehicle: SBVehicle, physics_world: SBWorld, hud_control: Control) -> void:
	map_id = id
	player = player_vehicle
	world = physics_world
	hud = hud_control
	reset()

func reset() -> void:
	_clock = -1.0
	_airborne = false
	_grounded = 0.0
	_last_pos = Vector3.INF
	_cooldown = 0.0

func _progress() -> Variant:
	var game := get_node_or_null("/root/Game")
	return game.progress if game else null


func status() -> String:
	var progress: Variant = _progress()
	if progress == null:
		return ""
	var best: Dictionary = progress.get_best_jump(map_id)
	return "" if best.is_empty() else "Sprung %.1f m" % float(best.get("distance_m", 0.0))

## Returns a landing event `{distance_m, airtime_s}` once, otherwise `{}`.
func observe(position: Vector3, speed_kmh: float, contact: bool, upright: float, now: float, dt: float) -> Dictionary:
	var teleported := _last_pos.is_finite() and position.distance_to(_last_pos) > TELEPORT_DISTANCE and dt < 0.5
	if teleported:
		_airborne = false
		_grounded = 0.0
	var was_grounded := _grounded
	if contact:
		_grounded += dt
	else:
		_grounded = 0.0
	var event := {}
	if not _airborne:
		if not contact and not teleported and absf(speed_kmh) >= MIN_SPEED_KMH and was_grounded >= 0.12:
			_airborne = true
			_start_time = now
			_start_pos = position
	else:
		if now - _start_time > MAX_JUMP_TIME:
			_airborne = false
		elif contact:
			_airborne = false
			var airtime := now - _start_time
			var distance := Vector2(position.x - _start_pos.x, position.z - _start_pos.z).length()
			if not teleported and upright > 0.45 and airtime >= MIN_AIRTIME and distance >= MIN_DISTANCE:
				event = {"distance_m": distance, "airtime_s": airtime}
	_last_pos = position
	return event

func _process(_delta: float) -> void:
	if not is_instance_valid(player) or world == null:
		return
	var now := float(world.get_stats()["sim_time"])
	if _clock < 0.0:
		_clock = now
		_last_pos = player.get_position_ws()
		return
	var dt := now - _clock
	_clock = now
	if dt <= 0.0:
		return
	_cooldown = maxf(0.0, _cooldown - dt)
	var loads := player.get_wheel_load()
	var contact := false
	for load in loads:
		if float(load) > 0.12:
			contact = true
			break
	var telemetry := player.get_telemetry()
	var event := observe(player.get_position_ws(), float(telemetry.get("speed_kmh", 0.0)), contact, player.get_up().y, now, dt)
	if event.is_empty() or _cooldown > 0.0:
		return
	_cooldown = 4.0
	var distance := float(event["distance_m"])
	var airtime := float(event["airtime_s"])
	var progress: Variant = _progress()
	if progress == null:
		return
	var best: Dictionary = progress.get_best_jump(map_id)
	var would_improve := best.is_empty() or distance > float(best.get("distance_m", 0.0))
	var saved: bool = progress.record_jump(map_id, distance, airtime)
	if not hud:
		return
	if would_improve and saved:
		hud.toast("Neuer Sprungrekord: %.1f m · %.2f s Luftzeit" % [distance, airtime])
	elif would_improve:
		hud.toast("Sprung: %.1f m · Rekord konnte nicht gespeichert werden" % distance)
	else:
		hud.toast("Sprung: %.1f m · %.2f s Luftzeit" % [distance, airtime])
