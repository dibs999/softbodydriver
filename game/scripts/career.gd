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

static func money_text(amount: float) -> String:
	var whole := roundi(amount)
	var digits := str(absi(whole))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0: grouped += "."
		grouped += digits[i]
	return ("-" if whole < 0 else "") + grouped + " €"
