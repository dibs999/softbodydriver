extends RefCounted
## Career rules (optional, off by default: the sandbox stays free). Activities pay, the service
## charges for fuel and repairs, and an instant repair anywhere costs a recovery fee on top. The
## balance lives in the player profile.

const START_MONEY := 2000.0
const FUEL_PRICE := 1.85          # EUR per litre
const RECOVERY_FEE := 150.0       # towing for an instant repair away from the service
const STARTER_CAR := "kestrel_hatch"   # owned from the start of a career

## Dealer price of a car from its game_state.cars entry: grows faster than the power, so the
## next car is a few activities away and the supercar a long way off. 250 EUR steps.
static func car_price(info: Dictionary) -> float:
	var kw := maxf(float(info.get("power", 0.0)), 40.0)
	return maxf(1000.0, roundf(4.0 * pow(kw, 1.4) / 250.0) * 250.0)

## Does the career own this car (id from the car file)?
static func owns(progress, car_id: String) -> bool:
	return car_id == STARTER_CAR or progress.owns_car(car_id)

## Pay for a finished activity (driving_activity's last_result).
static func payout(result: Dictionary) -> float:
	var mode := int(result.get("mode", 0))
	var medal := int(result.get("medal", 0))
	match mode:
		1:   # time trial
			return 120.0 + 140.0 * medal
		2:   # drift challenge: points, a little more for the medal
			return roundf(float(result.get("score", 0.0)) * 0.08) + 80.0 * medal
		3:   # deliveries: per stop delivered, a bonus for speed
			return 90.0 * float(result.get("checkpoints", 0)) + 100.0 * medal
		4:   # race by place
			var place := int(result.get("place", 0))
			return [0.0, 700.0, 380.0, 180.0][place] if place >= 1 and place <= 3 else 0.0
		5:   # crash test: the stars
			return 60.0 * float(result.get("crash", {}).get("stars", 0))
		6:   # pursuit: only an escape pays
			return (350.0 + 150.0 * medal) if bool(result.get("escaped", false)) else 0.0
	return 0.0

## Workshop bill for bringing a car back to new from its current telemetry: labour per broken and
## bent beam, plus parts for the damaged assemblies. A clean car costs nothing.
static func repair_cost(t: Dictionary) -> float:
	var broken := float(t.get("broken_beams", 0))
	var deformed := float(t.get("deformed_beams", 0))
	var parts := 0.0
	parts += 3200.0 * _amount(t.get("engine_damage", 0.0))
	parts += 650.0 * _amount(t.get("radiator_damage", 0.0))
	parts += 1900.0 * _amount(t.get("gearbox_damage", 0.0))
	parts += 900.0 * _amount(t.get("suspension_damage", 0.0))
	parts += 380.0 * _amount(t.get("rim_damage", 0.0))
	parts += 450.0 * _amount(t.get("fueltank_damage", 0.0))
	parts += 600.0 * _amount(t.get("paint_damage", 0.0))
	var labour := 18.0 * broken + 3.0 * deformed
	var total := labour + parts
	if total < 1.0:
		return 0.0
	return minf(roundf(60.0 + total), 12000.0)

## A damage value that may be a number or a list of per-part numbers (summed).
static func _amount(v: Variant) -> float:
	if v is float or v is int:
		return clampf(float(v), 0.0, 1.0)
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		var sum := 0.0
		for x in v: sum += clampf(float(x), 0.0, 1.0)
		return sum
	if v is bool:
		return 1.0 if v else 0.0
	return 0.0

## Contracts: each map offers one at a time, an activity on that map with a minimum medal and a
## bonus on top of the normal pay. The bonus grows with the contracts already done (up to double).
const CONTRACT_BASE := {1: 260.0, 2: 240.0, 3: 300.0, 4: 380.0, 5: 220.0, 6: 420.0}
const MODE_NAMES := ["Freie Fahrt", "Zeitfahren", "Drift-Challenge", "Lieferfahrt", "Rennen", "Crashtest", "Verfolgungsjagd"]
const MEDAL_NAMES := ["", "Bronze", "Silber", "Gold"]

## A new contract for a map from the modes it offers (free driving excluded). `serial` counts the
## contracts issued on this map, `done` those finished anywhere; both feed the seed so the next one
## differs from the last.
static func make_contract(map_id: String, modes: Array, serial: int, done: int) -> Dictionary:
	var pool: Array[int] = []
	for m in modes:
		if int(m) > 0 and CONTRACT_BASE.has(int(m)): pool.append(int(m))
	if pool.is_empty(): return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id) + serial * 7919 + done * 104729
	var mode: int = pool[rng.randi() % pool.size()]
	# Early contracts ask for bronze or silver; gold appears once a few are done.
	var top := 2 if done < 3 else 3
	var medal := rng.randi_range(1, top)
	var bonus := float(CONTRACT_BASE[mode]) * (0.7 + 0.45 * medal) * minf(1.0 + 0.1 * done, 2.0)
	return {"mode": mode, "medal": medal, "bonus": roundf(bonus / 10.0) * 10.0, "serial": serial}

static func contract_text(c: Dictionary) -> String:
	if c.is_empty(): return ""
	var mode := int(c.get("mode", 0))
	var medal := int(c.get("medal", 1))
	return "%s mit mindestens %s · Prämie %s" % [MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)], MEDAL_NAMES[clampi(medal, 1, 3)], money_text(float(c.get("bonus", 0.0)))]

## Does a finished activity (driving_activity's last_result) fulfil the contract?
static func fulfils(c: Dictionary, result: Dictionary) -> bool:
	return not c.is_empty() and int(result.get("mode", -1)) == int(c.get("mode", -2)) and int(result.get("medal", 0)) >= int(c.get("medal", 9))

static func money_text(amount: float) -> String:
	var whole := roundi(amount)
	var digits := str(absi(whole))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0: grouped += "."
		grouped += digits[i]
	return ("-" if whole < 0 else "") + grouped + " €"
