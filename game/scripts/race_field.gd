extends RefCounted
## Opponents for the "Rennen" activity: AI cars on a starting grid ahead of the player, held
## during the countdown, ranked by their progress through the same gates as the player.

const C := preload("res://scripts/maps/common.gd")

## AIDriver per opponent (created by the game scene, which owns the vehicles).
var drivers: Array = []
var gates := PackedVector3Array()
var next_gate: Array[int] = []
var finish_time: Array[float] = []
var _previous: Array[Vector3] = []


## Two cars side by side one row ahead of the start, further rows behind them.
static func grid(start: Transform3D, count: int) -> Array[Transform3D]:
	var fwd := start.basis.x
	var right := start.basis.z
	var out: Array[Transform3D] = []
	for i in count:
		var row := 1 + i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		out.append(Transform3D(start.basis, start.origin + fwd * (9.0 * row) + right * (side * 1.9)))
	return out


func setup(race_gates: PackedVector3Array, ai_drivers: Array) -> void:
	gates = race_gates
	drivers = ai_drivers
	next_gate.clear()
	finish_time.clear()
	_previous.clear()
	for d in drivers:
		next_gate.append(1)
		finish_time.append(-1.0)
		_previous.append(d.vehicle.get_position_ws() + Vector3.UP * 0.6)


func hold(on: bool) -> void:
	for d in drivers:
		d.hold = on


## Advances each opponent through the gates; returns the number that finished this call.
func update(elapsed: float, crossed: Callable) -> void:
	for i in drivers.size():
		var v: SBVehicle = drivers[i].vehicle
		if not is_instance_valid(v) or finish_time[i] >= 0.0:
			continue
		var p := v.get_position_ws()
		var g := next_gate[i]
		if g < gates.size():
			var forward := gates[g] - gates[g - 1]
			forward.y = 0
			if crossed.call(_previous[i], p, gates[g], forward.normalized()):
				next_gate[i] = g + 1
				if next_gate[i] >= gates.size():
					finish_time[i] = elapsed
		_previous[i] = p


## Race progress in gates (fractional towards the next gate).
func progress_of(position: Vector3, gate: int) -> float:
	if gate >= gates.size():
		return float(gates.size())
	var seg := gates[gate].distance_to(gates[gate - 1])
	var left := position.distance_to(gates[gate])
	return float(gate) - clampf(left / maxf(seg, 1.0), 0.0, 1.0)


## 1-based place of the player.
func place(player_position: Vector3, player_gate: int, player_finished: bool) -> int:
	var mine := float(gates.size()) + 1.0 if player_finished else progress_of(player_position, player_gate)
	var ahead := 0
	for i in drivers.size():
		if finish_time[i] >= 0.0:
			ahead += 1
			continue
		var v: SBVehicle = drivers[i].vehicle
		if is_instance_valid(v) and progress_of(v.get_position_ws(), next_gate[i]) > mine:
			ahead += 1
	return ahead + 1


func finished_count() -> int:
	return finish_time.filter(func(t: float) -> bool: return t >= 0.0).size()
