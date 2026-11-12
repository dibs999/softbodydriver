extends RefCounted
## "Bergen" (Home): puts a stuck or rolled car back where it last stood on all four wheels a few
## seconds ago, upright and at rest. Unlike the reset (R) the damage, fuel and tyre state stay as
## they are, so it only rescues the car, it does not repair it. Each further press goes further
## back along the trail.

const INTERVAL := 0.5     # simulation seconds between recorded poses
const MIN_AGE := 2.5      # the newest usable pose: the moment just before the trouble
const KEEP := 60          # poses kept (30 s)

var _poses: Array[Dictionary] = []   # {"t": sim time, "xform": Transform3D on the ground}
var _last := -1e9


func clear() -> void:
	_poses.clear()
	_last = -1e9


## Called every frame with the simulation clock. Records a pose only while all wheels carry load
## and the car is close to upright, so a recovery never lands it on a kerb, a roof or in the air.
func record(v: SBVehicle, sim_time: float) -> void:
	if sim_time < _last:
		clear()   # the world was rebuilt or rewound
	if sim_time - _last < INTERVAL:
		return
	var loads := v.get_wheel_load()
	if loads.is_empty():
		return
	for l in loads:
		if l <= 0.0:
			return
	var up := v.get_up().normalized()
	if up.y < 0.85:
		return
	var contacts: PackedVector3Array = v.get_effect_anchors().get("contacts", PackedVector3Array())
	if contacts.size() != loads.size():
		return
	var ground := Vector3.ZERO
	for c in contacts:
		ground += c
	ground /= contacts.size()
	var forward := v.get_forward()
	forward = (forward - up * forward.dot(up)).normalized()
	if not forward.is_finite() or forward.length_squared() < 0.5:
		return
	_last = sim_time
	_poses.append({"t": sim_time, "xform": Transform3D(Basis(forward, up, forward.cross(up)), ground)})
	if _poses.size() > KEEP:
		_poses.pop_front()


## Takes the newest pose at least MIN_AGE old and forgets everything after it. Returns null when
## there is none (just after a reset, or the car never stood on its wheels since).
func take(sim_time: float) -> Variant:
	while not _poses.is_empty() and sim_time - float(_poses.back()["t"]) < MIN_AGE:
		_poses.pop_back()
	if _poses.is_empty():
		return null
	var pose: Dictionary = _poses.pop_back()
	# Keep recording from the restored pose on, without an immediate duplicate of it.
	_last = sim_time
	return pose["xform"]
