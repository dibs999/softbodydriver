extends Node3D
## City traffic signals on a synchronised cycle. Traffic along X and along Z alternate:
## green 12 s, amber 3 s, all red 1 s. Lens materials are switched for all heads at once; AI
## drivers ask stop_distance() whether they must stop before the next intersection.

const GREEN_S := 12.0
const AMBER_S := 3.0
const ALL_RED_S := 1.0
const PERIOD := 2.0 * (GREEN_S + AMBER_S + ALL_RED_S)

var centers := PackedVector2Array()   # intersection centres (x, z)
var stop_offset := 9.0                # stop line distance from the centre
var clock := 0.0
## Lens materials per axis: [red, amber, green].
var lenses := {"x": [], "z": []}


## 0 = green, 1 = amber, 2 = red for traffic moving along `axis` ("x" or "z").
func state(axis: String, t := -1.0) -> int:
	var phase := fposmod(clock if t < 0.0 else t, PERIOD)
	if axis == "z":
		phase = fposmod(phase - (GREEN_S + AMBER_S + ALL_RED_S), PERIOD)
	if phase < GREEN_S:
		return 0
	if phase < GREEN_S + AMBER_S:
		return 1
	return 2


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var world: Node = scene.get("world") if scene else null
	var paused := world != null and bool(world.get("paused"))
	var scale := float(world.get("time_scale")) if world else 1.0
	if not paused:
		clock += delta * scale
	for axis in ["x", "z"]:
		var s := state(axis)
		var mats: Array = lenses[axis]
		for k in mats.size():
			var lit := (k == 0 and s == 2) or (k == 1 and s == 1) or (k == 2 and s == 0)
			(mats[k] as StandardMaterial3D).emission_energy_multiplier = 2.2 if lit else 0.0
			(mats[k] as StandardMaterial3D).albedo_color.a = 1.0


## Distance to the stop line of the next intersection ahead if its light requires stopping there,
## otherwise INF. Amber counts as stop when the line is still far enough away to stop comfortably.
func stop_distance(p: Vector3, forward: Vector3, speed: float) -> float:
	var axis := "x" if absf(forward.x) > absf(forward.z) else "z"
	var s := state(axis)
	if s == 0:
		return INF
	var dir := Vector2(signf(forward.x), 0.0) if axis == "x" else Vector2(0.0, signf(forward.z))
	var best := INF
	for c in centers:
		var rel := c - Vector2(p.x, p.z)
		var along := rel.dot(dir)
		var lateral := absf(rel.dot(Vector2(dir.y, -dir.x)))
		if lateral > 9.0 or along < stop_offset - 1.5 or along > 80.0:
			continue
		best = minf(best, along - stop_offset)
	if s == 1 and best < speed * speed / (2.0 * 3.5):
		return INF   # too close to stop on amber: clear the intersection
	return best
