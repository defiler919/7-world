extends Node2D
# 模块：layers/deep_sea/deep_sea_layer.gd
# 职责：深海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：生态建议(Intent)、时间(WorldClock tick)。
# 输出：LayerState（给 Debug / 未来 UI 用）。
# 禁止：跨层硬编码、直接访问其他层节点。

@export var layer_index: int = 0

@export var inertia_speed: float = 4.0 # 越大越“跟手”，越小越“黏”

var _target_intent: Dictionary = {}    # 每秒更新一次


# 如果你想保持 Inspector 可配置，也可以留着；但 Day4 推荐靠 Group 自动发现
var ecology_rules: Node = null
var clock: Node = null

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

var _accum := 0.0

func _ready() -> void:
	layer_state["layer_index"] = layer_index

	# 用 Group 找全局服务（你已加了 ecology_rules / world_clock）
	ecology_rules = get_tree().get_first_node_in_group("ecology_rules")
	clock = get_tree().get_first_node_in_group("world_clock")

	if ecology_rules == null:
		push_error("DeepSeaLayer: cannot find node in group 'ecology_rules'.")
		return
	if clock == null:
		push_error("DeepSeaLayer: cannot find node in group 'world_clock'.")
		return

	if clock.has_signal("tick_1s"):
		clock.tick_1s.connect(_on_tick_1s)
	else:
		set_process(true)



func _process(delta: float) -> void:
	# 让 world_time 始终跟着 clock（如果有）
	if clock != null and ("world_time" in clock):
		layer_state["world_time"] = float(clock.world_time)

	# 如果还没拿到目标 intent，先不平滑
	if _target_intent.is_empty():
		return

	var k: float = 1.0 - exp(-inertia_speed * delta) # 稳定的平滑系数（帧率无关）

	layer_state["spawn.fish_bias"] = lerp(
		float(layer_state.get("spawn.fish_bias", 0.0)),
		float(_target_intent.get("spawn.fish_bias", 0.0)),
		k
	)
	layer_state["spawn.algae_bias"] = lerp(
		float(layer_state.get("spawn.algae_bias", 0.0)),
		float(_target_intent.get("spawn.algae_bias", 0.0)),
		k
	)
	layer_state["death.fish_bias"] = lerp(
		float(layer_state.get("death.fish_bias", 0.0)),
		float(_target_intent.get("death.fish_bias", 0.0)),
		k
	)
	layer_state["invasion.risk"] = lerp(
		float(layer_state.get("invasion.risk", 0.0)),
		float(_target_intent.get("invasion.risk", 0.0)),
		k
	)
	layer_state["budget.spawn_points"] = lerp(
		float(layer_state.get("budget.spawn_points", 0.0)),
		float(_target_intent.get("budget.spawn_points", 0.0)),
		k
	)
	layer_state["env.pollution"] = lerp(
		float(layer_state.get("env.pollution", 0.0)),
		float(_target_intent.get("env.pollution", 0.0)),
		k
	)

	# version 直接跟随目标（不需要平滑）
	layer_state["intent_version"] = int(_target_intent.get("version", layer_state.get("intent_version", 0)))


func _on_tick_1s(world_time: float, _tick_index: int) -> void:
	layer_state["world_time"] = world_time

	if ecology_rules != null and ecology_rules.has_method("get_layer_intent"):
		_target_intent = ecology_rules.get_layer_intent(layer_index)


func _apply_intent(intent: Dictionary) -> void:
	layer_state["intent_version"] = int(intent.get("version", layer_state.get("intent_version", 0)))

	layer_state["spawn.fish_bias"] = float(intent.get("spawn.fish_bias", 0.0))
	layer_state["spawn.algae_bias"] = float(intent.get("spawn.algae_bias", 0.0))
	layer_state["death.fish_bias"] = float(intent.get("death.fish_bias", 0.0))
	layer_state["invasion.risk"] = float(intent.get("invasion.risk", 0.0))
	layer_state["budget.spawn_points"] = float(intent.get("budget.spawn_points", 0.0))
	layer_state["env.pollution"] = float(intent.get("env.pollution", 0.0))

func get_layer_state() -> Dictionary:
	return layer_state

func _find_single_in_group(group_name: StringName) -> Node:
	var arr := get_tree().get_nodes_in_group(group_name)
	if arr.size() == 0:
		return null
	# 如果未来出现多个，也先取第一个；之后我们再升级成“强校验”
	return arr[0] as Node
