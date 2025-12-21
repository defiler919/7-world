# res://core/layer/layer_base.gd
extends Node2D
class_name LayerBase

@export var tau_misc: float = 6.0
@export var max_rate_default: float = 0.0
@export var debug_enabled: bool = true

# 依赖：全局 class_name（你已经有 class_name InertiaField / LayerState）
var inertia := InertiaField.new()
var state := LayerState.new()

func _enter_tree() -> void:
	# ✅ 最关键：在 enter_tree 就加入 group，避免子类覆盖 _ready 忘了 super
	add_to_group("layers")

func _ready() -> void:
	# 默认 name 用节点名（子类也可以覆盖 state.name）
	state.name = StringName(name)

func _process(dt: float) -> void:
	var intent := get_layer_intent()
	if intent == null:
		return

	state.dt = dt
	state.intent = intent

	var flat_intent := _flatten_numeric(intent)

	var applied: Dictionary = {}
	var taus: Dictionary = {}

	for key in flat_intent.keys():
		var key_str := String(key)
		var target: float = float(flat_intent[key])
		var tau: float = _tau_for_key(key_str)

		inertia.set_tau(key_str, tau)
		if max_rate_default > 0.0:
			inertia.set_max_rate_if_absent(key_str, max_rate_default)

		var next: float = inertia.step(key_str, target, dt, tau)
		applied[key_str] = next
		taus[key_str] = tau

	state.applied = applied
	state.taus = taus

	_after_state_updated(state)

# -------------------------
# 子类需要实现/可覆盖
# -------------------------
func get_layer_intent() -> Dictionary:
	return {}

func _tau_for_key(_key: String) -> float:
	# 默认：全部走 misc（子类一般会按前缀分层 tau）
	return tau_misc

func _after_state_updated(_state: LayerState) -> void:
	pass

# -------------------------
# 通用工具：拍平（树形 -> "a.b.c" -> float）
# -------------------------
func _flatten_numeric(src: Dictionary, prefix: String = "") -> Dictionary:
	var out: Dictionary = {}

	for k in src.keys():
		var key_str := String(k)
		var full_key := key_str if prefix == "" else (prefix + "." + key_str)

		var v = src[k]
		if v is Dictionary:
			var sub := _flatten_numeric(v, full_key)
			for sk in sub.keys():
				out[sk] = sub[sk]
		else:
			var t := typeof(v)
			if t == TYPE_INT or t == TYPE_FLOAT:
				out[full_key] = float(v)

	return out
