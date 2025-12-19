extends Node2D
# 模块：layers/deep_sea/deep_sea_layer.gd
# 职责：深海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：生态“建议值”(Intent)、时间(WorldClock tick)。
# 输出：LayerState（给 Debug / 未来 UI 用）。

# =========================================================
# Day4：Intent 惯性（含“分层惯性 + 冲击加速”）
# =========================================================

# --- Inertia tuning (seconds) ---
@export var tau_spawn: float = 4.0        # spawn.* 快
@export var tau_death: float = 8.0        # death.* 中
@export var tau_budget: float = 10.0      # budget.* 中
@export var tau_risk: float = 30.0        # invasion.risk 慢
@export var tau_pollution: float = 45.0   # env.pollution 很慢（更“环境”）

# 冲击：当变化幅度超过阈值时，让 tau 变小（更快跟随）
@export var shock_threshold_spawn: float = 0.30
@export var shock_threshold_death: float = 0.20
@export var shock_threshold_budget: float = 0.50
@export var shock_threshold_risk: float = 0.15
@export var shock_threshold_pollution: float = 1.50

# 冲击时 tau 乘以这个倍率（越小越快）
@export var shock_tau_mul: float = 0.25

# 可选：整体快慢倍率（>1 更慢，<1 更快）
@export var tau_global_mul: float = 1.0


@export var layer_index: int = 0

# （保留：你之前的参数；现在主要不用它们，但先不删，避免你 Inspector 里已有配置丢失）
@export var intent_tau_seconds: float = 0.8
@export var pollution_tau_multiplier: float = 1.2


var ecology_rules: Node = null
var clock: Node = null

# 对外输出状态（DebugOverlay 读这个）
var layer_state: Dictionary = {
	"layer_index": 0,
	"world_time": 0.0,
	"intent_version": 0,

	"spawn.fish_bias": 0.0,
	"spawn.algae_bias": 0.0,
	"death.fish_bias": 0.0,
	"invasion.risk": 0.0,
	"budget.spawn_points": 0.0,
	"env.pollution": 0.0
}

# --- 惯性内部状态（保存“已应用值”）---
var _applied: Dictionary = {}
var _last_world_time: float = 0.0
var _accum := 0.0


func _ready() -> void:
	layer_state["layer_index"] = layer_index

	# 先按组查找（你已经加了 ecology_rules / world_clock 分组）
	ecology_rules = get_tree().get_first_node_in_group("ecology_rules")
	clock = get_tree().get_first_node_in_group("world_clock")

	if ecology_rules == null:
		push_error("DeepSeaLayer: cannot find node in group 'ecology_rules'.")
		return
	if clock == null:
		push_error("DeepSeaLayer: cannot find node in group 'world_clock'.")
		return

	# 初始化 applied 为当前 layer_state（第一帧不做突变）
	_applied = layer_state.duplicate(true)

	if clock.has_signal("tick_1s"):
		clock.tick_1s.connect(_on_tick_1s)
	else:
		set_process(true)


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 1.0:
		_accum -= 1.0
		_on_tick_1s(float(layer_state.get("world_time", 0.0)) + 1.0, 0)


# 由 tau 与 dt 计算“这一帧应该跟多少”
func _alpha(dt: float, tau: float) -> float:
	var t: float = maxf(0.001, tau) * tau_global_mul
	return 1.0 - exp(-dt / t)


# 按 key 分类，决定“平时的惯性强度”
func _tau_for_key(key: String) -> float:
	if key.begins_with("spawn."):
		return tau_spawn
	if key.begins_with("death."):
		return tau_death
	if key.begins_with("budget."):
		return tau_budget
	if key == "invasion.risk":
		return tau_risk
	if key == "env.pollution":
		return tau_pollution

	# 兜底：没归类的，给一个中等惯性
	return 8.0


# 按 key 分类，决定“冲击阈值”
func _shock_threshold_for_key(key: String) -> float:
	if key.begins_with("spawn."):
		return shock_threshold_spawn
	if key.begins_with("death."):
		return shock_threshold_death
	if key.begins_with("budget."):
		return shock_threshold_budget
	if key == "invasion.risk":
		return shock_threshold_risk
	if key == "env.pollution":
		return shock_threshold_pollution
	return 0.30


func _on_tick_1s(world_time: float, _tick_index: int) -> void:
	# 计算 dt（用于惯性）
	var dt: float = maxf(0.001, world_time - _last_world_time)
	_last_world_time = world_time

	layer_state["world_time"] = world_time

	# 取目标 intent
	var intent: Dictionary = {}
	if ecology_rules != null and ecology_rules.has_method("get_layer_intent"):
		intent = ecology_rules.get_layer_intent(layer_index)

	_apply_intent_with_inertia(intent, dt)


func _apply_intent_with_inertia(intent: Dictionary, dt: float) -> void:
	# 版本号照旧
	layer_state["intent_version"] = int(intent.get("version", layer_state.get("intent_version", 0)))

	# 需要惯性的 keys 列表（按你 layer_state 里的字段来）
	var keys: Array[String] = [
		"spawn.fish_bias",
		"spawn.algae_bias",
		"death.fish_bias",
		"invasion.risk",
		"budget.spawn_points",
		"env.pollution",
	]

	for k in keys:
		var target: float = float(intent.get(k, 0.0))
		var cur: float = float(_applied.get(k, 0.0))

		# 冲击判定：变化幅度超过阈值 -> tau 变小 -> 更快跟随
		var delta_abs: float = abs(target - cur)
		var tau: float = _tau_for_key(k)
		var th: float = _shock_threshold_for_key(k)
		if delta_abs >= th:
			tau *= shock_tau_mul

		var a: float = _alpha(dt, tau)
		var v: float = lerp(cur, target, a)

		_applied[k] = v
		layer_state[k] = v


func get_layer_state() -> Dictionary:
	return layer_state
