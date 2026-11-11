extends SceneTree
## Martinshorn of the interceptor: the synthesis alternates 440 and 585 Hz every 0.65 s, and with
## the light bar switched on the siren really reaches the AudioServer master mix near the car, at
## the same two pitches; switched off, it goes quiet.
## godot --headless -s res://tests/siren_test.gd
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

## Dominant pitch of a mono window from its zero crossings.
static func pitch(samples: PackedFloat32Array, rate: float) -> float:
	var crossings := 0
	for i in range(1, samples.size()):
		if (samples[i - 1] < 0.0) != (samples[i] < 0.0): crossings += 1
	return crossings * 0.5 * rate / samples.size()

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		_run()
	return false

func _run() -> void:
	var Beacons := preload("res://scripts/vehicle_beacons.gd")
	# Direct synthesis.
	var b = Beacons.new()
	var tone := b.render_siren(int(Beacons.RATE * 1.3))
	var first := PackedFloat32Array()
	var second := PackedFloat32Array()
	for i in range(int(Beacons.RATE * 0.1), int(Beacons.RATE * 0.55)): first.append(tone[i].x)
	for i in range(int(Beacons.RATE * 0.75), int(Beacons.RATE * 1.2)): second.append(tone[i].x)
	var f1 := pitch(first, Beacons.RATE)
	var f2 := pitch(second, Beacons.RATE)
	print("  synthesis: %.0f Hz then %.0f Hz" % [f1, f2])
	check(absf(f1 - 440.0) < 8.0 and absf(f2 - 585.0) < 8.0, "The horn alternates 440 and 585 Hz every 0.65 s")
	b.free()
	# Through the real mixer: an interceptor with the siren on, a camera (listener) beside it.
	var game := root.get_node("Game")
	var scene := Node3D.new()
	root.add_child(scene)
	var world := SBWorld.new()
	scene.add_child(world)
	world.add_ground_plane(1.0)
	var car: SBVehicle = game.spawn_vehicle(world, "res://cars/meridian_interceptor.car.json", Transform3D.IDENTITY)
	world.step_blocking(0.5)
	world.sync_visuals()
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = car.get_position_ws() + Vector3(-6, 1.5, 4)
	cam.current = true
	var beacons = car.get_node_or_null("Beacons")
	check(beacons != null, "The interceptor has its light bar and siren")
	if beacons == null:
		quit(1)
		return
	beacons.active = true
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, record)
	await create_timer(0.3).timeout
	record.set_recording_active(true)
	await create_timer(2.0).timeout
	record.set_recording_active(false)
	var captured := record.get_recording()
	var mono := PackedFloat32Array()
	var mix := float(AudioServer.get_mix_rate())
	if captured:
		mix = float(captured.mix_rate)
		var pcm: PackedByteArray = captured.data
		for i in pcm.size() / 4:
			mono.append((pcm.decode_s16(i * 4) + pcm.decode_s16(i * 4 + 2)) / 65536.0)
	var rms := 0.0
	for v in mono: rms += v * v
	rms = sqrt(rms / maxf(1.0, mono.size()))
	# Pitches over short windows: both tones of the horn turn up in the mixed output.
	var heard := []
	var window := int(mix * 0.2)
	for k in range(0, mono.size() - window, window):
		heard.append(roundi(pitch(mono.slice(k, k + window), mix)))
	print("  master capture: %d frames at %.0f Hz, rms %.3f, window pitches %s" % [mono.size(), mix, rms, str(heard)])
	check(mono.size() > mix and rms > 0.01, "The siren reaches the master mix at a clear level")
	var low := heard.any(func(f): return absf(float(f) - 440.0) < 25.0)
	var high := heard.any(func(f): return absf(float(f) - 585.0) < 25.0)
	check(low and high, "Both horn tones are in the mixed output")
	beacons.active = false
	await create_timer(0.3).timeout
	record.set_recording_active(true)
	await create_timer(0.4).timeout
	record.set_recording_active(false)
	var quiet := record.get_recording()
	var peak := 0
	if quiet:
		for i in range(0, quiet.data.size(), 2): peak = maxi(peak, absi(quiet.data.decode_s16(i)))
	print("  switched off: peak %d" % peak)
	check(peak < 300, "Switched off, the siren is silent")
	AudioServer.remove_bus_effect(0, effect_index)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
