extends SceneTree
const RainAudio := preload("res://scripts/weather_audio.gd")
const Weather := preload("res://scripts/world_weather.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func energy(frames: PackedVector2Array) -> Dictionary:
	var power := 0.0
	var peak := 0.0
	var difference := 0.0
	var previous := Vector2.ZERO
	for frame in frames:
		power += frame.length_squared()
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		difference += (frame - previous).length_squared()
		previous = frame
	return {"rms": sqrt(power / maxf(1, frames.size() * 2)), "peak": peak,
		"brightness": difference / maxf(0.000001, power)}
func export_pcm(frames: PackedVector2Array, path: String) -> void:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	for i in frames.size():
		pcm.encode_s16(i * 4, int(clampf(frames[i].x, -1, 1) * 32767))
		pcm.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1, 1) * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RainAudio.MIX_RATE
	wav.stereo = true
	wav.data = pcm
	check(wav.save_to_wav(path) == OK, "PCM rain sample saved")
func run() -> void:
	var source := RainAudio.new()
	root.add_child(source)
	source.set_process(false)
	source.set_conditions(1, false, 1, false, false, 1)
	source.render_frames(RainAudio.MIX_RATE)
	var exterior_frames: PackedVector2Array = source.render_frames(RainAudio.MIX_RATE * 2)
	var exterior := energy(exterior_frames)
	print("OUTDOOR RAIN ", exterior)
	check(exterior.rms > 0.01 and exterior.peak < 0.8, "Outdoor rain has nonzero audible-level signal and clipping headroom")
	export_pcm(exterior_frames, "/tmp/weather-rain-outdoor.wav")
	source.set_conditions(1, false, 1, true, false, 1)
	source.render_frames(RainAudio.MIX_RATE)
	var interior_frames: PackedVector2Array = source.render_frames(RainAudio.MIX_RATE * 2)
	var interior := energy(interior_frames)
	print("CABIN RAIN ", interior)
	check(interior.rms < exterior.rms * 0.65 and interior.brightness < exterior.brightness * 0.65, "Closed cabin attenuates and muffles rainfall")
	export_pcm(interior_frames, "/tmp/weather-rain-cabin.wav")
	source.set_conditions(1, false, 1, false, true, 1)
	source.render_frames(RainAudio.MIX_RATE)
	var canopy := energy(source.render_frames(RainAudio.MIX_RATE))
	check(canopy.rms > interior.rms and canopy.rms < exterior.rms, "Canopy has a distinct intermediate sheltered rain mix")
	source.set_conditions(1, false, 0.25, false, false, 0)
	check(energy(source.render_frames(1000)).peak == 0 and source._player.volume_linear == 0, "Master zero mutes synthesis and queued playback")
	check(source._player.pitch_scale == 0.25, "Rain playback follows simulation slow motion")
	source.set_conditions(1, false, 1, false, false, 1)
	source._process(0)
	source.set_conditions(1, true, 1, false, false, 1)
	check(source._player.stream_paused and energy(source.render_frames(1000)).peak == 0, "Pause freezes and silences rain")
	source.set_conditions(0, false, 1, false, false, 1)
	source.render_frames(RainAudio.MIX_RATE * 3)
	check(energy(source.render_frames(1000)).rms < 0.00001, "Clear weather fades the rain to silence")
	source._process(0)
	check(not source._player.playing, "Clear weather releases idle generator playback")
	check(Weather.doors_seal_cabin([]) and Weather.doors_seal_cabin([{"latched": true, "attached": true, "angle_degrees": 0.5}]), "Intact or unsupported door geometry retains cabin envelope")
	check(not Weather.doors_seal_cabin([{"latched": false}]) and not Weather.doors_seal_cabin([{"attached": false}]) and not Weather.doors_seal_cabin([{"angle_degrees": 12}]) and not Weather.doors_seal_cabin([{"missing": true}]), "Open, detached or missing door invalidates whole-cabin rain proxy")
	# Capture the actual AudioServer master output, in addition to direct synthesis metrics.
	var record := AudioEffectRecord.new()
	record.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, record)
	source.set_conditions(1, false, 1, false, false, 0.8)
	source.set_process(true)
	record.set_recording_active(true)
	await create_timer(1.5).timeout
	record.set_recording_active(false)
	var captured := record.get_recording()
	var capture_frames := PackedVector2Array()
	if captured:
		var pcm: PackedByteArray = captured.data
		capture_frames.resize(pcm.size() / 4)
		for i in capture_frames.size():
			capture_frames[i] = Vector2(pcm.decode_s16(i * 4), pcm.decode_s16(i * 4 + 2)) / 32768.0
		captured.save_to_wav("/tmp/weather-rain-master-capture.wav")
	var capture_stats := energy(capture_frames)
	print("AUDIO SERVER CAPTURE frames=", capture_frames.size(), " ", capture_stats)
	check(capture_frames.size() > 1000 and capture_stats.rms > 0.005, "Rain reaches the actual master mixer at nonzero level")
	source.set_conditions(1, false, 1, false, false, 0)
	await create_timer(0.20).timeout
	record.set_recording_active(true)
	await create_timer(0.30).timeout
	record.set_recording_active(false)
	var muted := record.get_recording()
	var muted_peak := 0
	if muted:
		for i in range(0, muted.data.size(), 2): muted_peak = maxi(muted_peak, absi(muted.data.decode_s16(i)))
	check(muted != null and muted.data.size() > 1000 and muted_peak == 0, "Master zero is silent in actual mixer capture")
	AudioServer.remove_bus_effect(0, effect_index)
	source.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failed else 0)
