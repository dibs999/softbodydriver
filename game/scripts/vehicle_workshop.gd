extends RefCounted
## Werkstatt (pause menu): parts and tuning per car, as in BeamNG's vehicle configuration. A
## configuration is a small dictionary of choices laid over the car file when the car is built:
## an engine from another car (with its own gearbox or the car's), engine tune and rev limit, final
## drive, drive layout and limited-slip differential, springs, dampers and anti-roll bars per axle,
## tyre compound, brake size and ballast. Applying it rebuilds the car where it stands.

## Neutral values: a configuration equal to these builds the car exactly as its file describes it.
const DEFAULTS := {
	"engine": "",          # car id whose engine goes in ("" = the car's own)
	"gearbox": "own",      # "own" keeps the car's gearbox, "donor" takes the donor car's
	"power": 1.0,          # engine tune: torque factor
	"limiter": 0.0,        # rev limiter offset, rpm
	"final_drive": 1.0,    # final drive ratio factor (higher = shorter, more pull, less top speed)
	"layout": "",          # "" original, "FWD", "RWD", "AWD"
	"lsd": -1.0,           # limited-slip preload factor (-1 = original)
	"spring_f": 1.0, "spring_r": 1.0,
	"damp_f": 1.0, "damp_r": 1.0,
	"arb_f": 1.0, "arb_r": 1.0,
	"compound": 1,         # index into COMPOUNDS
	"brakes": 1.0,         # brake torque factor (bigger discs and calipers)
	"ballast": 0.0,        # kg added (negative: weight stripped out)
	"ride_height": 0.0,    # ground clearance change, m (lowered / raised springs)
	"tire_width": 1.0,     # tyre width factor (narrower / wider tyres on the same rims)
}

## Tyre compounds: name and grip factor over the car's own tyres.
const COMPOUNDS := [["Eco (leichtlaufend)", 0.93], ["Straße (Serie)", 1.0], ["Sport", 1.08], ["Semi-Slick", 1.18]]
const LAYOUTS := [["Original", ""], ["Frontantrieb", "FWD"], ["Hinterradantrieb", "RWD"], ["Allrad", "AWD"]]

## Engine fields that travel with an engine swap (the brakes, tank and differential stay).
const ENGINE_KEYS := ["name", "cylinders", "torqueCurve", "idleRpm", "redlineRpm", "inertia", "friction",
	"engineBraking", "mass", "bsfc", "radiatorUA"]
const GEARBOX_KEYS := ["gears", "reverse", "finalDrive", "shiftUpRpm", "shiftDownRpm"]


static func normalized(cfg: Variant) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if cfg is Dictionary:
		for k in DEFAULTS.keys():
			if (cfg as Dictionary).has(k) and typeof(cfg[k]) == typeof(DEFAULTS[k]) or ((cfg as Dictionary).has(k) and (cfg[k] is float or cfg[k] is int) and (DEFAULTS[k] is float or DEFAULTS[k] is int)):
				out[k] = cfg[k]
	out["compound"] = clampi(int(out["compound"]), 0, COMPOUNDS.size() - 1)
	return out


static func is_default(cfg: Dictionary) -> bool:
	var n := normalized(cfg)
	for k in DEFAULTS.keys():
		if n[k] != DEFAULTS[k]:
			return false
	return true


static func read_definition(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Every engine in the game's cars, as {id, car, name, power_kw, torque_nm, cylinders, mass}.
static func engine_catalogue(cars: Array) -> Array:
	var out: Array = []
	for c: Dictionary in cars:
		var e: Dictionary = read_definition(c["path"]).get("engine", {})
		if e.is_empty():
			continue
		var peak_t := 0.0
		var peak_p := 0.0
		for p in e.get("torqueCurve", []):
			peak_t = maxf(peak_t, float(p[1]))
			peak_p = maxf(peak_p, float(p[1]) * float(p[0]) * TAU / 60.0 / 1000.0)
		out.append({"id": c["id"], "car": c["name"], "name": e.get("name", "?"), "power_kw": peak_p,
			"torque_nm": peak_t, "cylinders": int(e.get("cylinders", 4)), "mass": float(e.get("mass", 150.0)),
			"engine": e})
	out.sort_custom(func(a, b): return a["power_kw"] < b["power_kw"])
	return out


## The car file `definition` with configuration `cfg` applied (a new dictionary).
static func apply(definition: Dictionary, cfg: Dictionary, catalogue: Array) -> Dictionary:
	var c := normalized(cfg)
	var d: Dictionary = definition.duplicate(true)
	var e: Dictionary = d.get("engine", {})
	var chassis: Dictionary = d.get("chassis", {})
	# Engine swap: the donor's engine (and optionally its gearbox); the car keeps its brakes, tank,
	# differential and drive layout. The kerb weight changes by the difference in engine mass.
	if c["engine"] != "" and c["engine"] != d.get("id", ""):
		for entry: Dictionary in catalogue:
			if entry["id"] != c["engine"]:
				continue
			var donor: Dictionary = entry["engine"]
			var own_mass := float(e.get("mass", 150.0))
			var own_redline := float(e.get("redlineRpm", 6000.0))
			for k in ENGINE_KEYS:
				if donor.has(k):
					e[k] = donor[k].duplicate(true) if donor[k] is Array else donor[k]
			if c["gearbox"] == "donor":
				for k in GEARBOX_KEYS:
					if donor.has(k):
						e[k] = donor[k].duplicate(true) if donor[k] is Array else donor[k]
			else:
				# The car's gearbox, its shift points moved to the new engine's rev range.
				var scale := float(e["redlineRpm"]) / own_redline
				e["shiftUpRpm"] = minf(float(e.get("shiftUpRpm", own_redline - 600.0)) * scale, float(e["redlineRpm"]) - 300.0)
				e["shiftDownRpm"] = maxf(float(e.get("shiftDownRpm", 1800.0)) * scale, float(e.get("idleRpm", 800.0)) * 2.0)
			chassis["curbMass"] = float(chassis.get("curbMass", 1200.0)) + float(e.get("mass", own_mass)) - own_mass
			break
	if c["power"] != 1.0:
		var curve: Array = []
		for p in e.get("torqueCurve", []):
			curve.append([p[0], float(p[1]) * float(c["power"])])
		e["torqueCurve"] = curve
	if c["limiter"] != 0.0:
		e["redlineRpm"] = float(e.get("redlineRpm", 6000.0)) + float(c["limiter"])
		e["shiftUpRpm"] = minf(float(e.get("shiftUpRpm", 5500.0)) + float(c["limiter"]), float(e["redlineRpm"]) - 300.0)
	e["finalDrive"] = float(e.get("finalDrive", 4.0)) * float(c["final_drive"])
	if c["layout"] != "":
		e["layout"] = c["layout"]
	if c["lsd"] >= 0.0:
		e["lsd"] = float(c["lsd"])
	e["maxBrakeTorque"] = float(e.get("maxBrakeTorque", 2000.0)) * float(c["brakes"])
	var susp: Dictionary = d.get("suspension", {})
	for axle: String in ["front", "rear"]:
		if not susp.has(axle):
			continue
		var s: Dictionary = susp[axle]
		var f := axle == "front"
		s["wheelRate"] = float(s.get("wheelRate", 25000.0)) * float(c["spring_f" if f else "spring_r"])
		var damp := float(c["damp_f" if f else "damp_r"])
		s["bumpDamping"] = float(s.get("bumpDamping", 2000.0)) * damp
		s["reboundDamping"] = float(s.get("reboundDamping", 4000.0)) * damp
		s["antiRollRate"] = float(s.get("antiRollRate", 6000.0)) * float(c["arb_f" if f else "arb_r"])
	var tires: Dictionary = d.get("tires", {})
	tires["friction"] = float(tires.get("friction", 1.0)) * float(COMPOUNDS[c["compound"]][1])
	tires["width"] = float(tires.get("width", 0.22)) * float(c["tire_width"])
	var body: Dictionary = d.get("body", {})
	if c["ride_height"] != 0.0:
		body["groundClearance"] = maxf(0.07, float(body.get("groundClearance", 0.14)) + float(c["ride_height"]))
	chassis["curbMass"] = float(chassis.get("curbMass", 1200.0)) + float(c["ballast"])
	return d


## Path to build the car from: the car file itself, or (configured) a copy with the configuration
## applied, written to user://configured/.
static func configured_path(path: String, cfg: Dictionary, catalogue: Array) -> String:
	if cfg.is_empty() or is_default(cfg):
		return path
	var definition := read_definition(path)
	if definition.is_empty():
		return path
	var out := apply(definition, cfg, catalogue)
	DirAccess.make_dir_recursive_absolute("user://configured")
	var target := "user://configured/%s.car.json" % str(definition.get("id", path.get_file().get_basename()))
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return path
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return target


## One line for the toast: what the configuration changes.
static func summary(cfg: Dictionary, catalogue: Array) -> String:
	var c := normalized(cfg)
	var parts: Array[String] = []
	if c["engine"] != "":
		for entry: Dictionary in catalogue:
			if entry["id"] == c["engine"]:
				parts.append("Motor %s" % entry["name"])
	if c["power"] != 1.0: parts.append("Leistung %+d %%" % int(round((c["power"] - 1.0) * 100.0)))
	if c["layout"] != "": parts.append(c["layout"])
	if c["compound"] != 1: parts.append(COMPOUNDS[c["compound"]][0])
	if c["ballast"] != 0.0: parts.append("%+d kg" % int(c["ballast"]))
	if c["ride_height"] != 0.0: parts.append("Höhe %+d mm" % int(round(c["ride_height"] * 1000.0)))
	return "Serienstand" if parts.is_empty() else ", ".join(parts)
