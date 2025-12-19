extends Node2D
# 模块：layers/deep_sea/deep_sea_layer.gd
# 职责：深海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：生态“建议值”(Intent)、时间(WorldClock tick)。
# 输出：LayerState（给 Debug / 未来 UI 用）。

@export var layer_index: int = 1

# --- Day4: Intent 惯性参数 ---
# 越大 = 跟随越慢、滑得更久；越小 = 更“粘手”、更快停
# 建议范围：0.3 ~ 2.0
@export var intent_tau_seconds: float = 0.8

# 如果你希望某些字段更稳，可以单独加权（可选）
@export var pollution_tau_multiplier: float = 1.2  # 污染变化更慢一点（更“惯性”）

var ecology_rules: Node = null
var clock: Node = null

# 对外输出状态（DebugOverlay 读这个）
var layer_state: Dictionary = {
	"layer_index": 1,
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
		_on_tick_1s(layer_state.get("world_time", 0.0) + 1.0, 0)

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
	# version 直接记录（不做惯性）
	layer_state["intent_version"] = int(intent.get("version", layer_state.get("intent_version", 0)))

	# --- 显式 float，避免 Variant 推断 ---
	var tau: float = maxf(0.001, float(intent_tau_seconds))
	var alpha: float = 1.0 - exp(-dt / tau)

	# 取值都强转为 float（关键）
	var target_spawn_fish: float = float(intent.get("spawn.fish_bias", 0.0))
	var target_spawn_algae: float = float(intent.get("spawn.algae_bias", 0.0))
	var target_death_fish: float = float(intent.get("death.fish_bias", 0.0))
	var target_invasion: float = float(intent.get("invasion.risk", 0.0))
	var target_budget: float = float(intent.get("budget.spawn_points", 0.0))
	var target_pollution: float = float(intent.get("env.pollution", 0.0))

	var cur_spawn_fish: float = float(_applied.get("spawn.fish_bias", 0.0))
	var cur_spawn_algae: float = float(_applied.get("spawn.algae_bias", 0.0))
	var cur_death_fish: float = float(_applied.get("death.fish_bias", 0.0))
	var cur_invasion: float = float(_applied.get("invasion.risk", 0.0))
	var cur_budget: float = float(_applied.get("budget.spawn_points", 0.0))
	var cur_pollution: float = float(_applied.get("env.pollution", 0.0))

	_applied["spawn.fish_bias"] = _lerp_float(cur_spawn_fish, target_spawn_fish, alpha)
	_applied["spawn.algae_bias"] = _lerp_float(cur_spawn_algae, target_spawn_algae, alpha)
	_applied["death.fish_bias"] = _lerp_float(cur_death_fish, target_death_fish, alpha)
	_applied["invasion.risk"] = _lerp_float(cur_invasion, target_invasion, alpha)
	_applied["budget.spawn_points"] = _lerp_float(cur_budget, target_budget, alpha)

	# 污染可更慢
	var pollution_tau: float = maxf(0.001, tau * float(pollution_tau_multiplier))
	var pollution_alpha: float = 1.0 - exp(-dt / pollution_tau)
	_applied["env.pollution"] = _lerp_float(cur_pollution, target_pollution, pollution_alpha)

	# 写回对外 layer_state
	layer_state["spawn.fish_bias"] = float(_applied["spawn.fish_bias"])
	layer_state["spawn.algae_bias"] = float(_applied["spawn.algae_bias"])
	layer_state["death.fish_bias"] = float(_applied["death.fish_bias"])
	layer_state["invasion.risk"] = float(_applied["invasion.risk"])
	layer_state["budget.spawn_points"] = float(_applied["budget.spawn_points"])
	layer_state["env.pollution"] = float(_applied["env.pollution"])


func _lerp_float(a: float, b: float, t: float) -> float:
	var tt: float = clampf(t, 0.0, 1.0)
	return a + (b - a) * tt


func get_layer_state() -> Dictionary:
	return layer_state
