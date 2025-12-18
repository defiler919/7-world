extends Node2D
# 模块：layers/shallow_sea/shallow_sea_layer.gd
# 职责：浅海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：本层配置、生态“建议值”(Intent)、时间(WorldClock tick)。
# 输出：LayerState（给 WorldRoot / Debug / 未来 UI 用）。
# 禁止：跨层硬编码、直接访问其他层节点。

@export var layer_index: int = 0

# 依赖注入：用 NodePath + get_node_or_null，避免 class_name 顺序问题
@export var ecology_rules_path: NodePath
@export var clock_path: NodePath

var ecology_rules: Node = null
var clock: Node = null

# 本层只读状态（先用 Dictionary，后续你想换成 Resource/Script class 也行）
var layer_state: Dictionary = {
	"layer_index": 0,
	"world_time": 0.0,

	# Debug/观测用
	"intent_version": 0,

	# 生态建议（缓存）
	"spawn.fish_bias": 0.0,
	"spawn.algae_bias": 0.0,
	"death.fish_bias": 0.0,
	"invasion.risk": 0.0,
	"budget.spawn_points": 0.0,
	"env.pollution": 0.0
}

# 兜底 tick（如果 clock 没信号）
var _accum := 0.0

func _ready() -> void:
	layer_state["layer_index"] = layer_index

	ecology_rules = get_node_or_null(ecology_rules_path)
	clock = get_node_or_null(clock_path)

	if ecology_rules == null:
		push_error("ShallowSeaLayer: ecology_rules_path not found.")
		return
	if clock == null:
		push_error("ShallowSeaLayer: clock_path not found.")
		return

	# 接入 WorldClock tick_1s(world_time, tick_index)
	if clock.has_signal("tick_1s"):
		clock.tick_1s.connect(_on_tick_1s)
	else:
		# 兜底：没有 tick 就用 _process 每秒跑一次
		set_process(true)

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 1.0:
		_accum -= 1.0
		_on_tick_1s(layer_state.get("world_time", 0.0) + 1.0, 0)

func _on_tick_1s(world_time: float, _tick_index: int) -> void:
	layer_state["world_time"] = world_time

	# 读取本层 intent（你的 EcologyRules 里返回 Dictionary，越界返回 {}）
	var intent: Dictionary = {}
	if ecology_rules != null and ecology_rules.has_method("get_layer_intent"):
		intent = ecology_rules.get_layer_intent(layer_index)

	_apply_intent(intent)

func _apply_intent(intent: Dictionary) -> void:
	# intent 为空时也不报错，保持可运行
	layer_state["intent_version"] = int(intent.get("version", layer_state.get("intent_version", 0)))

	layer_state["spawn.fish_bias"] = float(intent.get("spawn.fish_bias", 0.0))
	layer_state["spawn.algae_bias"] = float(intent.get("spawn.algae_bias", 0.0))
	layer_state["death.fish_bias"] = float(intent.get("death.fish_bias", 0.0))
	layer_state["invasion.risk"] = float(intent.get("invasion.risk", 0.0))
	layer_state["budget.spawn_points"] = float(intent.get("budget.spawn_points", 0.0))
	layer_state["env.pollution"] = float(intent.get("env.pollution", 0.0))

# 对外接口：给 WorldRoot / DebugOverlay 读取
func get_layer_state() -> Dictionary:
	return layer_state
