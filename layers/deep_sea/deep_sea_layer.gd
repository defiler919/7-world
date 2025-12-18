extends Node2D
# 模块：layers/deep_sea/deep_sea_layer.gd
# 职责：深海层容器：承载本层内容并输出本层状态（LayerState）。
# 输入：本层配置、生态“建议值”(Intent)、时间(WorldClock tick)。
# 输出：LayerState（给 WorldRoot / Debug / 未来 UI 用）。
# 禁止：跨层硬编码、直接访问其他层节点。

@export var layer_index: int = 1

@export var ecology_rules_path: NodePath
@export var clock_path: NodePath

# ✅ 新增：深海背景（用一个 ColorRect 当背景即可）
@export var background_rect_path: NodePath

var ecology_rules: Node = null
var clock: Node = null
var background_rect: ColorRect = null

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

var _accum := 0.0

func _ready() -> void:
	layer_state["layer_index"] = layer_index

	ecology_rules = get_node_or_null(ecology_rules_path)
	clock = get_node_or_null(clock_path)
	background_rect = get_node_or_null(background_rect_path) as ColorRect

	if ecology_rules == null:
		push_error("DeepSeaLayer: ecology_rules_path not found.")
		return
	if clock == null:
		push_error("DeepSeaLayer: clock_path not found.")
		return
	if background_rect == null:
		push_error("DeepSeaLayer: background_rect_path not found (please point to a ColorRect).")
		return

	if clock.has_signal("tick_1s"):
		clock.tick_1s.connect(_on_tick_1s)
	else:
		set_process(true)

	# 启动时先刷一次，避免第一秒之前画面不更新
	_apply_visual_from_pollution(float(layer_state.get("env.pollution", 0.0)))

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 1.0:
		_accum -= 1.0
		_on_tick_1s(layer_state.get("world_time", 0.0) + 1.0, 0)

func _on_tick_1s(world_time: float, _tick_index: int) -> void:
	layer_state["world_time"] = world_time

	var intent: Dictionary = {}
	if ecology_rules != null and ecology_rules.has_method("get_layer_intent"):
		intent = ecology_rules.get_layer_intent(layer_index)

	_apply_intent(intent)

func _apply_intent(intent: Dictionary) -> void:
	layer_state["intent_version"] = int(intent.get("version", layer_state.get("intent_version", 0)))

	layer_state["spawn.fish_bias"] = float(intent.get("spawn.fish_bias", 0.0))
	layer_state["spawn.algae_bias"] = float(intent.get("spawn.algae_bias", 0.0))
	layer_state["death.fish_bias"] = float(intent.get("death.fish_bias", 0.0))
	layer_state["invasion.risk"] = float(intent.get("invasion.risk", 0.0))
	layer_state["budget.spawn_points"] = float(intent.get("budget.spawn_points", 0.0))
	layer_state["env.pollution"] = float(intent.get("env.pollution", 0.0))

	# ✅ 生态 -> 画面（最小闭环）
	_apply_visual_from_pollution(layer_state["env.pollution"])

func _apply_visual_from_pollution(pollution: float) -> void:
	if background_rect == null:
		return

	# 0..30 映射到 0..1
	var p: float = clamp(pollution / 30.0, 0.0, 1.0)

	var clean: Color = Color(0.05, 0.20, 0.55, 1.0)
	var dirty: Color = Color(0.10, 0.18, 0.25, 1.0)

	var brightness: float = lerp(1.0, 0.55, p)

	var c: Color = clean.lerp(dirty, p)
	c.r *= brightness
	c.g *= brightness
	c.b *= brightness

	background_rect.color = c


func get_layer_state() -> Dictionary:
	return layer_state
