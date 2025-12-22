# ============================================================
# 模块宪法：ecology/ecology_bus.gd
# ============================================================
# 【是什么】
# EcologyBus 是“生态系统的事实/修改请求总线（轻量数据汇聚）”
#
# 【负责什么】
# - 存储事实（facts）：如 env.pollution / invasion.risk / debug.last_event
# - 存储修改请求（mods）：如 add/mul（未来事件系统/调试系统可能会用）
#
# 【不负责什么】
# ❌ 不驱动生态规则（那是 ecology_rules.gd 的职责）
# ❌ 不改场景节点，不改相机，不改世界结构
# ============================================================

extends Resource
class_name EcologyBus

# --- facts: 最新事实快照 ---
var _facts_global: Dictionary = {}
var _facts_by_layer: Dictionary = {} # layer_id -> Dictionary

# --- mods: 事件/系统提出的“修改请求”（可选） ---
var _add_global: Dictionary = {}
var _add_by_layer: Dictionary = {} # layer_id -> Dictionary

var _mul_global: Dictionary = {}
var _mul_by_layer: Dictionary = {} # layer_id -> Dictionary

# --- world time snapshot (optional) ---
var _world_time: float = 0.0

func setup(_layer_count: int) -> void:
	# 目前不需要预分配，保留接口以便 Rules/Runner 调用
	pass

func begin_tick(world_time: float) -> void:
	_world_time = world_time
	# 每个 tick 可以选择清空 mods（事实不清）
	_add_global.clear()
	_add_by_layer.clear()
	_mul_global.clear()
	_mul_by_layer.clear()

func get_world_time() -> float:
	return _world_time


# ------------------------------------------------------------
# Facts API
# ------------------------------------------------------------
func push_fact(key: String, value, layer_id: StringName = &"") -> void:
	if layer_id == &"":
		_facts_global[key] = value
		return

	# ✅ 安全拿 dict：第一次写入可能没有
	var d: Dictionary = {}
	if _facts_by_layer.has(layer_id):
		var v = _facts_by_layer[layer_id]
		if typeof(v) == TYPE_DICTIONARY:
			d = v
		else:
			# 防御：被污染成了非字典（不应该发生，但别崩）
			d = {}
	else:
		d = {}

	d[key] = value
	_facts_by_layer[layer_id] = d

func get_facts(layer_id: StringName = &"") -> Dictionary:
	if layer_id == &"":
		return _facts_global.duplicate(true)

	if not _facts_by_layer.has(layer_id):
		return {}

	var v = _facts_by_layer[layer_id]
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return (v as Dictionary).duplicate(true)


# ------------------------------------------------------------
# Mod API: add
# ------------------------------------------------------------
func push_add(key: String, delta: float, layer_id: StringName = &"") -> void:
	if layer_id == &"":
		_add_global[key] = float(_add_global.get(key, 0.0)) + delta
		return

	var d: Dictionary = {}
	if _add_by_layer.has(layer_id):
		var v = _add_by_layer[layer_id]
		if typeof(v) == TYPE_DICTIONARY:
			d = v
		else:
			d = {}
	else:
		d = {}

	d[key] = float(d.get(key, 0.0)) + delta
	_add_by_layer[layer_id] = d

func get_mod_add(layer_id: StringName = &"") -> Dictionary:
	if layer_id == &"":
		return _add_global.duplicate(true)

	if not _add_by_layer.has(layer_id):
		return {}

	var v = _add_by_layer[layer_id]
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return (v as Dictionary).duplicate(true)


# ------------------------------------------------------------
# Mod API: mul
# ------------------------------------------------------------
func push_mul(key: String, factor: float, layer_id: StringName = &"") -> void:
	if layer_id == &"":
		_mul_global[key] = float(_mul_global.get(key, 1.0)) * factor
		return

	var d: Dictionary = {}
	if _mul_by_layer.has(layer_id):
		var v = _mul_by_layer[layer_id]
		if typeof(v) == TYPE_DICTIONARY:
			d = v
		else:
			d = {}
	else:
		d = {}

	d[key] = float(d.get(key, 1.0)) * factor
	_mul_by_layer[layer_id] = d

func get_mod_mul(layer_id: StringName = &"") -> Dictionary:
	if layer_id == &"":
		return _mul_global.duplicate(true)

	if not _mul_by_layer.has(layer_id):
		return {}

	var v = _mul_by_layer[layer_id]
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return (v as Dictionary).duplicate(true)
