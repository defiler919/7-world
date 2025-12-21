# res://core/layer/inertia_field.gd
extends RefCounted
class_name InertiaField

var values: Dictionary = {}     # key -> float
var taus: Dictionary = {}       # key -> float
var max_rate: Dictionary = {}   # key -> float

func set_tau(key: String, tau: float) -> void:
	taus[key] = max(0.0001, tau)

func set_max_rate(key: String, rate: float) -> void:
	max_rate[key] = rate

func set_max_rate_if_absent(key: String, rate: float) -> void:
	if not max_rate.has(key):
		max_rate[key] = rate

func get_value(key: String, default_value: float = 0.0) -> float:
	return float(values.get(key, default_value))

func ensure_key(key: String, init_value: float, default_tau: float) -> void:
	if not values.has(key):
		values[key] = init_value
	if not taus.has(key):
		taus[key] = max(0.0001, default_tau)

func step(key: String, target: float, dt: float, default_tau: float) -> float:
	ensure_key(key, target, default_tau)

	var current: float = float(values[key])
	var tau: float = float(taus.get(key, default_tau))
	tau = max(0.0001, tau)

	var alpha: float = 1.0 - exp(-dt / tau)
	var next: float = current + (target - current) * alpha

	var rate: float = float(max_rate.get(key, 0.0))
	if rate > 0.0:
		var max_delta: float = rate * dt
		var delta: float = next - current
		if abs(delta) > max_delta:
			next = current + sign(delta) * max_delta

	values[key] = next
	return next
