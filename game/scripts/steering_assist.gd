extends RefCounted
## Bound assisted input by a plausible cornering demand, rather than a fixed
## fraction of parking lock. The physics still determines grip and vehicle motion.
const LOCK_RADIANS := deg_to_rad(34.0)
const LATERAL_DEMAND := 1.1 * 9.81

static func limit(speed_kmh: float, wheelbase: float = 2.8) -> float:
	var speed := absf(speed_kmh) / 3.6
	if speed < 1.0:
		return 1.0
	var road_angle := atan(LATERAL_DEMAND * clampf(wheelbase, 1.5, 4.5) / (speed * speed))
	# The generated steering linkage actuates tie-rod travel (sin of wheel angle).
	return clampf(sin(road_angle) / sin(LOCK_RADIANS), 0.0, 1.0)

static func apply(input: float, speed_kmh: float, wheelbase: float = 2.8) -> float:
	return clampf(input, -1.0, 1.0) * limit(speed_kmh, wheelbase)
