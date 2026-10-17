class_name TuxHaptics
extends Node
## Short distance-scaled handheld pulses; unsupported platforms safely do nothing.
signal pulse_requested(duration_ms: int, strength: float)
const RANGE := 3.0
const COOLDOWN_MS := 120
var last_pulse_ms := -1000

func explosion(point: Vector2, cells: Array) -> bool:
	var distance := RANGE
	for cell in cells:
		distance = minf(distance, point.distance_to(Vector2(cell)))
	if distance >= RANGE: return false
	var now := Time.get_ticks_msec()
	if now - last_pulse_ms < COOLDOWN_MS: return false
	last_pulse_ms = now
	var proximity := 1.0 - distance / RANGE
	var duration := roundi(lerpf(35.0, 110.0, proximity))
	var strength := lerpf(0.2, 0.8, proximity)
	pulse_requested.emit(duration, strength)
	Input.vibrate_handheld(duration, strength)
	return true
