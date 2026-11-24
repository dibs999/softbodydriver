extends SceneTree
## Synthetic jump detection: enough ground contact arms the tracker, a real airborne flight is
## measured once at landing, while small bumps, rollovers and teleports do not count.
## godot --headless -s res://tests/stunt_tracker_test.gd
const StuntTracker := preload("res://scripts/stunt_tracker.gd")
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func grounded(t, frames := 10) -> void:
	for i in frames:
		t.observe(Vector3.ZERO, 60.0, true, 1.0, i * 0.02, 0.02)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var t := StuntTracker.new()
	grounded(t)
	var now := 0.3
	check(t.observe(Vector3.ZERO, 62.0, false, 1.0, now, 0.02).is_empty(), "Takeoff itself reports no landing")
	for i in range(1, 24):
		now += 0.025
		check(t.observe(Vector3(i * 0.9, 2.0, 0), 62.0, false, 1.0, now, 0.025).is_empty(), "No event while airborne")
	now += 0.025
	var event: Dictionary = t.observe(Vector3(21.6, 0.1, 0), 58.0, true, 1.0, now, 0.025)
	check(not event.is_empty() and absf(float(event["distance_m"]) - 21.6) < 0.2 and float(event["airtime_s"]) > 0.5, "Clean landing measures distance and airtime")
	check(t.observe(Vector3(22.5, 0, 0), 50.0, true, 1.0, now + 0.025, 0.025).is_empty(), "Landing is reported only once")

	t = StuntTracker.new()
	grounded(t)
	now = 0.3
	t.observe(Vector3.ZERO, 60.0, false, 1.0, now, 0.02)
	now += 0.1
	t.observe(Vector3(2.0, 0.5, 0), 59.0, false, 1.0, now, 0.1)
	now += 0.1
	check(t.observe(Vector3(4.0, 0, 0), 58.0, true, 1.0, now, 0.1).is_empty(), "Short bump is not a scored jump")

	t = StuntTracker.new()
	grounded(t)
	now = 0.3
	t.observe(Vector3.ZERO, 65.0, false, 1.0, now, 0.02)
	for i in range(1, 24):
		now += 0.025
		t.observe(Vector3(i * 0.9, 2.0, 0), 62.0, false, 0.2, now, 0.025)
	now += 0.025
	check(t.observe(Vector3(21.6, 0.1, 0), 20.0, true, 0.2, now, 0.025).is_empty(), "Landing upside down is not a clean jump")

	t = StuntTracker.new()
	grounded(t)
	now = 0.3
	t.observe(Vector3.ZERO, 65.0, false, 1.0, now, 0.02)
	now += 0.05
	check(t.observe(Vector3(200.0, 0, 0), 65.0, true, 1.0, now, 0.05).is_empty(), "Teleport does not fabricate jump distance")
	print("STUNT TRACKER TEST ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
