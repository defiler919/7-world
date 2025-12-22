# ============================================================
# 模块宪法：ecology/event_runner.gd
# ============================================================
#
# 【这个模块是什么？】
# EventRunner 是“事件运行器”（调度 + 生命周期）。
# 它不直接改生态规则，只向 EcologyBus 投递 modifiers。
#
# 【它负责什么？】
# ✅ per-layer：启动 / tick / 结束事件
# ✅ 冷却：防止事件频繁触发
# ✅ 输出：把事件影响 push 到 bus（mul/add/fact）
#
# 【它不负责什么？】
# ❌ 不写 UI / DebugOverlay（DebugOverlay 只读）
# ❌ 不直接操作实体（鱼/草的生死由 Spawner 读取 applied 决定）
#
# ============================================================
# res://ecology/event_runner.gd
extends Node
class_name EventRunner

@export var allow_multi_events: bool = false
@export var cooldown_min: float = 30.0
@export var cooldown_max: float = 90.0
@export var duration_min: float = 20.0
@export var duration_max: float = 50.0
@export var base_chance_per_min: float = 0.08

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# layer_id -> { active: Array[Dictionary], cooldown_left: float }
var _layer_runtime: Dictionary = {}

var _meta_ref: Variant = null

func set_meta_ref(m: Variant) -> void:
	_meta_ref = m

func tick(bus: Variant, dt: float, meta: Variant = null) -> void:
	var m: Variant = meta
	if m == null:
		m = _meta_ref

	var layer_ids: Array[StringName] = []

	if m != null:
		# meta 是 Dictionary：用 has/[]
		if (m is Dictionary) and (m as Dictionary).has("layer_ids") and (((m as Dictionary)["layer_ids"]) is Array):
			var raw: Array = (m as Dictionary)["layer_ids"]
			for x in raw:
				layer_ids.append(StringName(String(x)))

		# meta 是 Object：才能 has_method/call
		elif (m is Object) and (m as Object).has_method("get_layer_ids"):
			var raw2: Variant = (m as Object).call("get_layer_ids")
			if raw2 is Array:
				for x in (raw2 as Array):
					layer_ids.append(StringName(String(x)))

	for layer_id: StringName in layer_ids:
		_tick_layer(bus, dt, layer_id)

func _tick_layer(bus: Variant, dt: float, layer_id: StringName) -> void:
	if not _layer_runtime.has(layer_id):
		_layer_runtime[layer_id] = {
			"active": [],
			"cooldown_left": 0.0
		}

	var rt: Dictionary = _layer_runtime[layer_id]
	var active: Array = rt["active"]
	var cooldown_left: float = float(rt["cooldown_left"])

	cooldown_left = maxf(0.0, cooldown_left - dt)
	rt["cooldown_left"] = cooldown_left

	if not active.is_empty():
		for i in range(active.size() - 1, -1, -1):
			var ev: Dictionary = active[i]
			ev["elapsed"] = float(ev.get("elapsed", 0.0)) + dt
			active[i] = ev

			_emit_event_to_bus(bus, layer_id, ev)

			var dur: float = float(ev.get("duration", 0.0))
			if dur > 0.0 and float(ev["elapsed"]) >= dur:
				active.remove_at(i)

		if active.is_empty():
			rt["cooldown_left"] = _rng.randf_range(cooldown_min, cooldown_max)

	if active.is_empty() and float(rt["cooldown_left"]) <= 0.0:
		_try_start_one(layer_id, dt)

	_layer_runtime[layer_id] = rt

func _try_start_one(layer_id: StringName, dt: float) -> void:
	var chance_per_sec: float = base_chance_per_min / 60.0
	var p: float = 1.0 - pow(1.0 - chance_per_sec, dt)

	var seed_i: int = int(Time.get_ticks_msec()) ^ int(hash(String(layer_id)))
	_rng.seed = seed_i

	if _rng.randf() >= p:
		return

	var dur: float = _rng.randf_range(duration_min, duration_max)
	var ev: Dictionary = {
		"id": "deep_invasion",
		"elapsed": 0.0,
		"duration": dur,
		"strength": _rng.randf_range(0.2, 1.0)
	}

	var rt: Dictionary = _layer_runtime[layer_id]
	var active: Array = rt["active"]

	if (not allow_multi_events) and (not active.is_empty()):
		return

	active.append(ev)
	rt["active"] = active
	_layer_runtime[layer_id] = rt

func _emit_event_to_bus(bus: Variant, layer_id: StringName, ev: Dictionary) -> void:
	if not (bus is Object):
		return
	var b := bus as Object
	if not b.has_method("push_add"):
		return

	var id: String = String(ev.get("id", ""))
	if id == "deep_invasion":
		var strength: float = float(ev.get("strength", 0.0))
		b.call("push_add", "invasion.risk", strength * 0.02, layer_id)

func get_layer_event_debug(layer_id: StringName) -> Dictionary:
	if not _layer_runtime.has(layer_id):
		return {"active": [], "cooldown_left": 0.0}
	return _layer_runtime[layer_id]
