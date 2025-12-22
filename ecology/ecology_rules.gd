# ============================================================
# 模块宪法：ecology/ecology_rules.gd
# ============================================================
#
# 【这个模块是什么？】
# EcologyRules 是“生态规则引擎（Rules Engine）”，负责：
# - 每秒推进生态状态（鱼/草/污染等）
# - 生成各层的 Intent（建议值），交给各 Layer 的 InertiaField 做平滑应用
# - 作为 Debug / UI / 日志 的统一数据来源（通过 get_layer_state / get_layer_intent）
#
# ------------------------------------------------------------
# 【它负责什么？】
# 1) 维护每层 EcologyLayerState（状态快照，可读）
# 2) 维护每层 Intent（建议值，可读）
# 3) 推进：稳定态生态 + 危机脉冲（事件系统提供脉冲，不在这里硬编码事件）
#
# ------------------------------------------------------------
# 【它不负责什么？（非常重要）】
# ❌ 不直接生成/删除实体（Spawner 执行）
# ❌ 不画面表现（Vignette/Visuals 执行）
# ❌ 不做输入响应（WorldRoot/Camera 做）
# ❌ 不在此处写“某个事件的剧情逻辑”
#
# ------------------------------------------------------------
# 【事件系统接入原则】
# - 事件由 EventRunner 负责“何时触发/持续多久”
# - EcologyRules 只读取 EcologyBus 的“本 tick 修改量/事实/标记”，并把它们折算到状态与 intent
# - EcologyRules 不保存“事件剧情状态机”，最多保存“危机恢复计时器/恢复系数”等纯数值
#
# ============================================================

extends Node
class_name EcologyRules

# ------------------------------------------------------------
# 依赖（你已经创建好的文件）
# ------------------------------------------------------------
# - res://ecology/ecology_layer_state.gd  (Resource: EcologyLayerState)
# - res://ecology/ecology_bus.gd          (Resource: EcologyBus)
# - res://ecology/event_runner.gd         (Node: EventRunner)
#
# 注意：这里不会假设你把 EventRunner 做成 Autoload。
# 我们会：如果场景树里找不到，就在本节点下创建一个（最稳）。
# ------------------------------------------------------------

@export var layer_count: int = 2

# ----------------------------
# 生态“容量/目标”参数
# ----------------------------
@export var fish_cap_default: float = 50.0
@export var algae_cap_default: float = 80.0

# 稳定态：鱼/草回到目标的速度（越小越慢）
@export var fish_recover_tau: float = 45.0     # 秒：鱼数量回到目标的时间尺度
@export var algae_recover_tau: float = 30.0    # 秒：草数量回到目标的时间尺度

# 污染：稳定态 + 危机脉冲（不会无限增长）
@export var pollution_baseline: float = 0.0
@export var pollution_relax_tau: float = 80.0  # 秒：污染回到基线的时间尺度
@export var pollution_from_low_algae: float = 0.6  # 草低于阈值时污染缓慢上升
@export var algae_low_ratio: float = 0.25      # 草低于 25% 容量算“偏低”

# ----------------------------
# “危机风险”显示（给 Vignette 用）
# ----------------------------
# 这里的 invasion.risk 是“当前危机强度”，不应永久为 1。
@export var risk_relax_tau: float = 25.0       # 秒：危机结束后风险衰减时间尺度
@export var risk_floor: float = 0.0            # 最小风险（长期稳定可为 0）
@export var risk_ceiling: float = 1.0

# ----------------------------
# Intent 映射参数（把状态折算为建议值）
# ----------------------------
@export var spawn_bias_base: float = 1.0
@export var algae_spawn_bias_base: float = 1.0
@export var death_fish_bias_base: float = 0.0

# budget：给 spawner 的“可执行预算”，越大越容易补回来
@export var budget_base: float = 2.8
@export var budget_min: float = 0.6
@export var budget_max: float = 5.0
@export var budget_pollution_k: float = 0.06

# ------------------------------------------------------------
# 内部状态
# ------------------------------------------------------------
var _intent_version: int = 0
var _world_time: float = 0.0

var layer_states: Array = []     # Array[EcologyLayerState]
var layer_intents: Array = []    # Array[Dictionary]

var _bus: Resource = null        # EcologyBus
var _event_runner: Node = null   # EventRunner

# 一点点“恢复系数/冷却”类的纯数值 meta（不放剧情）
var _meta := {
	"recover_left": {},   # layer_id -> seconds
	"event_active": {},   # layer_id -> bool
}

# ------------------------------------------------------------
# Godot 生命周期
# ------------------------------------------------------------
func _ready() -> void:
	_init_states()
	_init_intents()

	# ✅ bus：生态数据总线（事实/增量/乘法修正）
	_bus = _get_or_create_bus()

	# ✅ event_runner：事件调度（触发/持续/结束）
	_event_runner = _get_or_create_event_runner()

	# 如果你用 WorldClock 1s tick，这里尽量自动连接（有则连，无则不报错）
	_try_connect_world_clock()

func _process(dt: float) -> void:
	_world_time += dt

# WorldClock 每秒 tick 进来（允许不同签名：_on_tick_1s() / _on_tick_1s(dt) / _on_tick_1s(dt, world_time)）
func _on_tick_1s(dt: float = 1.0, world_time: float = -1.0) -> void:
	var t := _world_time if world_time < 0.0 else world_time

	# 1) bus 开始一个 tick（清空上一 tick 的临时增量/事实）
	if _bus != null and _bus.has_method("begin_tick"):
		_bus.begin_tick(t)

	# 2) 事件调度：让 event_runner 往 bus 里写“事件事实/修正”
	#    统一用 3 参数调用：tick(bus, dt, meta)
	if _event_runner != null and _event_runner.has_method("tick"):
		_event_runner.tick(_bus, dt, _meta)

	# 3) 推进每层生态（稳定态 + bus 的事件脉冲/修正）
	for i in range(layer_states.size()):
		_step_layer(i, dt)

	# 4) 全局 hazard（可选）
	_step_global_hazards(dt)

	# 5) 重新生成 intents（给各 layer 读取）
	_rebuild_intents(t)

	_intent_version += 1

# ------------------------------------------------------------
# 初始化：states / intents
# ------------------------------------------------------------
func _init_states() -> void:
	layer_states.clear()
	for i in range(layer_count):
		var s = _new_layer_state(i)
		layer_states.append(s)

func _init_intents() -> void:
	layer_intents.clear()
	for i in range(layer_count):
		layer_intents.append({})
	_intent_version = 0

func _new_layer_state(i: int):
	# EcologyLayerState 是 Resource，你项目里已有
	var s = EcologyLayerState.new()
	# 下面这些字段以“尽量兼容”为目标：如果你 state 里没有这些字段，也不会影响 intent 输出
	if "layer_index" in s:
		s.layer_index = i
	if "fish" in s:
		s.fish = fish_cap_default * 0.25
	if "algae" in s:
		s.algae = algae_cap_default * 0.35
	if "pollution" in s:
		s.pollution = pollution_baseline
	return s

# ------------------------------------------------------------
# 核心推进：每层生态
# ------------------------------------------------------------
func _step_layer(i: int, dt: float) -> void:
	var s = layer_states[i]
	var layer_id: StringName = StringName("layer_%d" % i)

	# 读取当前数量（如果 state 没字段，就用默认）
	var fish: float = float(s.fish) if "fish" in s else 0.0
	var algae: float = float(s.algae) if "algae" in s else 0.0
	var pollution: float = float(s.pollution) if "pollution" in s else 0.0

	# 容量（你未来可以每层不同，这里先用默认）
	var fish_cap := fish_cap_default
	var algae_cap := algae_cap_default

	# ----------------------------
	# 1) 稳定态目标
	# ----------------------------
	# 目标：长期维持而不是末日
	# - 草：自适应（更快回到目标）
	# - 鱼：慢一点回到目标
	var fish_target: float = clamp(fish_cap * 0.30, 0.0, fish_cap)
	var algae_target: float = clamp(algae_cap * 0.40, 0.0, algae_cap)

	# ----------------------------
	# 2) bus 事件脉冲 / 修正（只读）
	# ----------------------------
	# 约定：
	# - bus.get_mod_add(key, layer_id) : float
	# - bus.get_mod_mul(key, layer_id) : float (默认 1)
	# - bus.get_facts(layer_id)        : Dictionary
	var add_pollution := _bus_get_add("env.pollution", layer_id)
	var mul_pollution := _bus_get_mul("env.pollution", layer_id)

	var add_risk := _bus_get_add("invasion.risk", layer_id)
	var mul_risk := _bus_get_mul("invasion.risk", layer_id)

	var facts := _bus_get_facts(layer_id)

	# ----------------------------
	# 3) 污染：稳定态回落 + 草不足时缓升 + 事件脉冲
	# ----------------------------
	# (A) 草偏低 -> 污染缓慢上升（生态压力，不会爆表）
	var algae_ratio := 0.0 if algae_cap <= 0.0 else algae / algae_cap
	var eco_pressure := 0.0
	if algae_ratio < algae_low_ratio:
		eco_pressure = (algae_low_ratio - algae_ratio) / max(0.0001, algae_low_ratio) # 0..1
	# (B) 污染目标 = baseline + eco_pressure * k + 事件 add（事件用 add 体现脉冲）
	var pollution_target := pollution_baseline + eco_pressure * pollution_from_low_algae + add_pollution
	pollution_target *= mul_pollution

	# 指数回归到目标（不会无限增长）
	pollution = _exp_relax(pollution, pollution_target, dt, pollution_relax_tau)
	pollution = max(0.0, pollution)

	# ----------------------------
	# 4) 草：只要系统允许，永远可回补（你要的“草不会灭绝”）
	# ----------------------------
	# 草受污染影响：污染越高，草回补速度越慢，但不会变成负增长到灭绝
	var algae_recover_scale := 1.0 / (1.0 + pollution * 0.15)
	algae = _exp_relax(algae, algae_target, dt, algae_recover_tau / max(0.15, algae_recover_scale))
	algae = clamp(algae, 0.0, algae_cap)

	# ----------------------------
	# 5) 鱼：危机期间会掉（由事件系统通过 facts / add_risk 影响）
	# ----------------------------
	# 这里不写“入侵是什么”，只看事件系统是否给了“fish_loss_rate”
	var fish_loss_rate := 0.0
	if facts.has("fish_loss_rate"):
		fish_loss_rate = float(facts["fish_loss_rate"]) # 每秒损失比例（0.0~1.0）

	# 危机损失（脉冲），同时 fish 会向 fish_target 回补
	if fish_loss_rate > 0.0:
		fish *= clamp(1.0 - fish_loss_rate * dt, 0.0, 1.0)

	fish = _exp_relax(fish, fish_target, dt, fish_recover_tau)
	fish = clamp(fish, 0.0, fish_cap)

	# ----------------------------
	# 6) 写回 state（只写我们确定存在的字段）
	# ----------------------------
	if "fish" in s:
		s.fish = fish
	if "algae" in s:
		s.algae = algae
	if "pollution" in s:
		s.pollution = pollution

	# ----------------------------
	# 7) 写回“恢复计时器”meta（纯数值，不写剧情）
	# ----------------------------
	# 事件可在 meta.event_active[layer_id]=true 时表示“危机中”
	var active := false
	if _meta.has("event_active") and _meta["event_active"].has(layer_id):
		active = bool(_meta["event_active"][layer_id])

	# 如果危机结束，给一个“恢复窗口”让风险更快下降（不写到 state）
	if not active:
		_meta["recover_left"][layer_id] = max(0.0, float(_meta["recover_left"].get(layer_id, 0.0)) - dt)
	else:
		_meta["recover_left"][layer_id] = max(float(_meta["recover_left"].get(layer_id, 0.0)), 8.0)

	# ----------------------------
	# 8) 计算“当前风险”供 intent 使用（不写到 state，避免你之前 s.risk 报错）
	# ----------------------------
	# 风险来自事件系统的 add/mul（脉冲），并在无事件时指数衰减到 floor
	var prev_risk := float(facts.get("_risk_prev", 0.0))
	var base_risk_target: float = clamp(add_risk * mul_risk, 0.0, 1.0)

	# 如果处于恢复窗口，衰减更快一点
	var rr := float(_meta["recover_left"].get(layer_id, 0.0))
	var tau := risk_relax_tau
	if rr > 0.0:
		tau *= 0.55

	var risk := _exp_relax(prev_risk, base_risk_target, dt, tau)
	risk = clamp(risk, risk_floor, risk_ceiling)

	# 把 risk 临时塞回 facts 里（仅供本 tick 的 intent 生成，不当成“事件剧情状态”）
	facts["_risk_prev"] = risk
	_bus_set_facts(layer_id, facts)

# ------------------------------------------------------------
# 可选：全局 hazards（先留空，不做末日系统）
# ------------------------------------------------------------
func _step_global_hazards(_dt: float) -> void:
	# 预留：将来你可以做跨层影响（比如“深海风暴影响浅海”）
	pass

# ------------------------------------------------------------
# 生成 Intent（对外输出给 LayerBase）
# ------------------------------------------------------------
func _rebuild_intents(world_time: float) -> void:
	for i in range(layer_states.size()):
		var s = layer_states[i]
		var layer_id: StringName = StringName("layer_%d" % i)

		var fish: float = float(s.fish) if "fish" in s else 0.0
		var algae: float = float(s.algae) if "algae" in s else 0.0
		var pollution: float = float(s.pollution) if "pollution" in s else 0.0

		var fish_cap := fish_cap_default
		var algae_cap := algae_cap_default

		# 取出我们在 _step_layer 里缓存的 risk
		var facts := _bus_get_facts(layer_id)
		var risk: float = float(facts.get("_risk_prev", 0.0))

		# spawn bias：缺口越大，越偏向补
		var fish_missing: float = clamp((fish_cap - fish) / max(1.0, fish_cap), 0.0, 1.0)
		var algae_missing: float = clamp((algae_cap - algae) / max(1.0, algae_cap), 0.0, 1.0)

		var fish_bias: float = spawn_bias_base + fish_missing * 1.2
		var algae_bias: float = algae_spawn_bias_base + algae_missing * 1.2

		# 污染越高，鱼死亡倾向越高（但这只是“建议值”，真正如何执行交给 layer/spawner）
		var death_fish: float = clamp(death_fish_bias_base + pollution * 0.05 + risk * 0.35, 0.0, 1.0)

		# budget：污染越高 budget 越低，但有下限（保证长期能回补）
		var budget: float = budget_base - (pollution * budget_pollution_k)
		budget = clamp(budget, budget_min, budget_max)

		# 组装 intent（保持你 debug_overlay 的字段命名）
		var intent: Dictionary = {
			"version": _intent_version,
			"world_time": world_time,
			"layer_index": i,

			# 建议：spawn
			"spawn.fish_bias": fish_bias,
			"spawn.algae_bias": algae_bias,

			# 建议：death
			"death.fish_bias": death_fish,

			# 建议：危机强度（给 vignette）
			"invasion.risk": risk,

			# 建议：预算
			"budget.spawn_points": budget,

			# Debug：环境（你现在 overlay 在看它）
			"env.pollution": pollution
		}

		# 事件系统也可能想直接修正某些 key（例如把 invasion.risk 拉高一点）
		intent = _apply_bus_mods_to_intent(intent, layer_id)

		layer_intents[i] = intent

# bus 修正：支持 add/mul（不在这里定义事件，只做数学合并）
func _apply_bus_mods_to_intent(intent: Dictionary, layer_id: StringName) -> Dictionary:
	# 只处理你现阶段会显示/用到的 key（未来可以扩展）
	var keys := [
		"spawn.fish_bias",
		"spawn.algae_bias",
		"death.fish_bias",
		"invasion.risk",
		"budget.spawn_points",
		"env.pollution"
	]

	for k in keys:
		var base := float(intent.get(k, 0.0))
		var add := _bus_get_add(k, layer_id)
		var mul := _bus_get_mul(k, layer_id)
		intent[k] = (base + add) * mul

	# 保底 clamp（避免事件写坏）
	intent["death.fish_bias"] = clamp(float(intent.get("death.fish_bias", 0.0)), 0.0, 1.0)
	intent["invasion.risk"] = clamp(float(intent.get("invasion.risk", 0.0)), 0.0, 1.0)
	intent["budget.spawn_points"] = clamp(float(intent.get("budget.spawn_points", budget_base)), budget_min, budget_max)
	intent["env.pollution"] = max(0.0, float(intent.get("env.pollution", 0.0)))

	return intent

# ------------------------------------------------------------
# 对外 API（Debug / LayerBase 读取）
# ------------------------------------------------------------
func get_layer_intent(layer_index: int) -> Dictionary:
	if layer_index < 0 or layer_index >= layer_intents.size():
		return {}
	return layer_intents[layer_index]

func get_world_intent() -> Dictionary:
	# 目前世界级 intent 先留空（以后可放天气/昼夜等“世界态”）
	return {
		"version": _intent_version,
		"world_time": _world_time
	}

func get_intent_version() -> int:
	return _intent_version

func get_layer_state(layer_index: int):
	if layer_index < 0 or layer_index >= layer_states.size():
		return null
	return layer_states[layer_index]

# ------------------------------------------------------------
# bus / event_runner 获取与兼容层
# ------------------------------------------------------------
func _get_or_create_bus() -> Resource:
	# 优先：如果你已经在别处 new 过并挂在某个节点 meta 上，也可以自己改这里的获取逻辑
	var b = EcologyBus.new()
	return b

func _get_or_create_event_runner() -> Node:
	# 1) 先看看自己子树里有没有
	var n:= get_node_or_null("EventRunner")
	if n != null:
		return n
	var  r := EventRunner.new()
	r.name = "EventRunner"
	add_child(r)
	return r


func _try_connect_world_clock() -> void:
	# 尝试找一个名为 WorldClock 的节点（按你项目结构 res://core/time/world_clock.gd）
	var candidates := get_tree().get_nodes_in_group("world_clock")
	if not candidates.is_empty():
		var wc = candidates[0]
		# 期望它有信号 tick_1s(dt, world_time) 或 tick_1s()
		if wc.has_signal("tick_1s"):
			# 用 call_deferred 防止 ready 顺序问题
			call_deferred("_deferred_connect_tick", wc)
			return

	# 如果没有 group，尝试全树扫描同名节点
	var root := get_tree().root
	var wc2 := root.get_node_or_null("WorldClock")
	if wc2 != null and wc2.has_signal("tick_1s"):
		call_deferred("_deferred_connect_tick", wc2)

func _deferred_connect_tick(wc: Node) -> void:
	if wc == null:
		return
	if wc.has_signal("tick_1s"):
		# 避免重复连接
		if not wc.is_connected("tick_1s", Callable(self, "_on_tick_1s")):
			wc.connect("tick_1s", Callable(self, "_on_tick_1s"))

# ------------------------------------------------------------
# 小工具：指数回归（稳定系统的关键）
# ------------------------------------------------------------
func _exp_relax(cur: float, target: float, dt: float, tau: float) -> float:
	if tau <= 0.0001:
		return target
	var k := 1.0 - exp(-dt / tau)
	return cur + (target - cur) * k

# ------------------------------------------------------------
# bus 兼容封装（避免方法参数个数不一致导致崩）
# ------------------------------------------------------------
func _bus_get_add(key: String, layer_id: StringName) -> float:
	if _bus == null:
		return 0.0

	if not (_bus is Object):
		return 0.0

	var b := _bus as Object
	if not b.has_method("get_mod_add"):
		return 0.0

	var argc := b.get_method_argument_count("get_mod_add")

	# 旧版：get_mod_add(key)
	if argc <= 1:
		return _to_float(b.call("get_mod_add", key), 0.0)

	# 新版：get_mod_add(key, layer_id)
	return _to_float(b.call("get_mod_add", key, layer_id), 0.0)


func _bus_get_mul(key: String, layer_id: StringName) -> float:
	if _bus == null:
		return 1.0

	if not (_bus is Object):
		return 1.0

	var b := _bus as Object
	if not b.has_method("get_mod_mul"):
		return 1.0

	var argc := b.get_method_argument_count("get_mod_mul")

	# 旧版：get_mod_mul(key)
	if argc <= 1:
		return _to_float(b.call("get_mod_mul", key), 1.0)

	# 新版：get_mod_mul(key, layer_id)
	return _to_float(b.call("get_mod_mul", key, layer_id), 1.0)



func _bus_get_facts(layer_id: StringName) -> Dictionary:
	if _bus == null:
		return {}
	if _bus.has_method("get_facts"):
		var d = _bus.get_facts(layer_id)
		return d if d is Dictionary else {}
	return {}

func _bus_set_facts(layer_id: StringName, facts: Dictionary) -> void:
	if _bus == null:
		return
	if _bus.has_method("_set_facts_unsafe"):
		# 如果你在 bus 里提供了内部方法，就用它（更快）
		_bus._set_facts_unsafe(layer_id, facts)
		return
	# 没有就退化：逐项 push_fact（比较慢，但安全）
	if _bus.has_method("push_fact"):
		for k in facts.keys():
			_bus.push_fact(String(k), facts[k], layer_id)
func _to_float(v: Variant, default_value: float) -> float:
	if v == null:
		return default_value
	var t := typeof(v)
	if t == TYPE_FLOAT:
		return v
	if t == TYPE_INT:
		return float(v) if false else (v * 1.0) # 防止 float() 被当构造器：用 *1.0
	return default_value
