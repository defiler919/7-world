# ============================================================
# 模块宪法：debug/debug_overlay.gd
# ============================================================
#
# 【这个模块是什么？】
# DebugOverlay 是一个“只读调试显示层”（HUD / 仪表盘）。
#
# 它的唯一职责是：
# 👉 把 WorldRoot 提供的 WorldState（以及可选的其他只读系统）
#    以人类可读的方式显示在屏幕左上角。
#
# 【它负责什么？】
# 1) 每帧读取 WorldRoot.get_world_state()
# 2) 读取 EcologyRules 的 Intent（只读）
# 3) 把数据格式化为文本
# 4) 显示在屏幕上
#
# 【它不负责什么？】
# ❌ 不修改世界状态
# ❌ 不参与任何逻辑决策
# ❌ 不驱动相机/不切层/不触发生态
#
# ============================================================

extends CanvasLayer

@export var world_root_path: NodePath
@export var ecology_rules_path: NodePath
@export var max_debug_lines: int = 32

var world_root: Node = null
var ecology_rules: Node = null

@onready var label := Label.new()

func _ready() -> void:
	# --- 依赖注入 ---
	world_root = get_node_or_null(world_root_path)
	if world_root == null:
		push_error("DebugOverlay: world_root_path not found.")
		return

	ecology_rules = get_node_or_null(ecology_rules_path)
	if ecology_rules == null:
		push_warning("DebugOverlay: ecology_rules_path not found. (Ecology section disabled)")

	# --- Label 初始化 ---
	label.name = "DebugLabel"
	label.position = Vector2(12, 12)
	label.text = "[World Debug]\n(waiting...)"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label)

func _process(_delta: float) -> void:
	if world_root == null:
		return
	if not world_root.has_method("get_world_state"):
		return

	var state = world_root.get_world_state()
	if state == null:
		return

	label.text = _limit_lines(_format_all(state), max_debug_lines)

# ============================================================
# 格式化总入口
# ============================================================

func _format_all(state) -> String:
	var text := ""
	var layer_index := int(state.current_layer_index)

	text += _format_world_block(state)
	text += "\n"
	text += _format_ecology_intent_block(layer_index)
	text += "\n"
	text += _format_layer_applied_block(layer_index)

	return text

# ============================================================
# World 基础信息
# ============================================================

func _format_world_block(state) -> String:
	var s := ""
	s += "[World Debug]\n"
	s += "Layer: %d\n" % int(state.current_layer_index)
	s += "Col: %d\n" % int(state.current_col_index)
	s += "Camera Center: (%.1f, %.1f)\n" % [state.camera_center.x, state.camera_center.y]
	s += "Local Offset: (%.1f, %.1f)\n" % [state.camera_local_offset.x, state.camera_local_offset.y]
	s += "Viewport: %.0f x %.0f\n" % [state.viewport_size.x, state.viewport_size.y]
	s += "Cooldown: %.2f\n" % float(state.switch_cooldown_left)
	s += "World Time: %.2f\n" % float(state.world_time)
	return s

# ============================================================
# Ecology Intent（建议值）
# ============================================================

func _format_ecology_intent_block(layer_index: int) -> String:
	if ecology_rules == null:
		# 生态系统不存在/没挂上 → 给提示但不报错
		return "[Ecology Intent]\n(not connected)\n"

	# EcologyRules 必须提供 get_layer_intent(layer_index)
	if not ecology_rules.has_method("get_layer_intent"):
		return "[Ecology Intent]\n(no get_layer_intent)\n"

	var intent: Dictionary = ecology_rules.get_layer_intent(layer_index)
	if intent.is_empty():
		return "[Ecology Intent]\n(empty)\n"

	var s := ""
	s += "[Ecology Intent]\n"
	s += "version: %d  time: %.2f\n" % [
		int(intent.get("version", 0)),
		float(intent.get("world_time", 0.0))
	]
	s += "spawn.fish_bias: %.2f\n" % float(intent.get("spawn.fish_bias", 0.0))
	s += "spawn.algae_bias: %.2f\n" % float(intent.get("spawn.algae_bias", 0.0))
	s += "death.fish_bias: %.2f\n" % float(intent.get("death.fish_bias", 0.0))
	s += "invasion.risk: %.2f\n" % float(intent.get("invasion.risk", 0.0))
	s += "budget.spawn_points: %.2f\n" % float(intent.get("budget.spawn_points", 0.0))
	s += "env.pollution: %.2f\n" % float(intent.get("env.pollution", 0.0))
	s += "\n"
	s += _format_population_block(layer_index)

	return s

# ============================================================
# Population（当前层的实体数量，只读）
# ============================================================

func _format_population_block(state_any: Variant) -> String:
	# ------------------------------------------------------------
	# Population（只读）
	# 兼容两种调用方式：
	#   A) 传 WorldState / Object：读取 current_layer_index
	#   B) 传 int：直接当作 layer_index
	# ------------------------------------------------------------

	if world_root == null:
		return "[Population]\n(no world_root)\n"

	# world_root 必须有 layers 成员
	if not ("layers" in world_root):
		return "[Population]\n(world_root has no layers)\n"

	var layers_var: Variant = world_root.layers
	if layers_var == null or not (layers_var is Array):
		return "[Population]\n(layers invalid)\n"

	var layers: Array = layers_var
	if layers.is_empty():
		return "[Population]\n(no layers)\n"

	# --- 1) 解析 idx（兼容 int / Dictionary / Object） ---
	var idx_val: Variant = null

	# B) 直接传了 int/float（比如你现在 state_any=0）
	if typeof(state_any) == TYPE_INT or typeof(state_any) == TYPE_FLOAT:
		idx_val = int(state_any)

	# A1) 传了 Dictionary
	elif state_any is Dictionary:
		var d: Dictionary = state_any
		idx_val = d.get("current_layer_index", null)

	# A2) 传了 Object（WorldState 这种）
	elif state_any is Object:
		# Object.get("prop")：属性不存在会返回 null（不会崩）
		idx_val = (state_any as Object).get("current_layer_index")

	if idx_val == null:
		return "[Population]\n(no layer index)\n"

	var idx: int = int(idx_val)
	if idx < 0 or idx >= layers.size():
		return "[Population]\n(layer index out of range: %d)\n" % idx

	# --- 2) 拿到层节点 ---
	var layer_node_var: Variant = layers[idx]
	if layer_node_var == null or not is_instance_valid(layer_node_var):
		return "[Population]\n(layer invalid)\n"

	var layer_node: Node = layer_node_var as Node

	# --- 3) 拿 Spawner 并读取 get_population_state() ---
	var spawner: Node = layer_node.get_node_or_null("Spawner")
	if spawner == null:
		return "[Population]\n(no spawner)\n"

	if not spawner.has_method("get_population_state"):
		return "[Population]\n(spawner has no get_population_state)\n"

	var p: Dictionary = spawner.call("get_population_state")
	var fish: int = int(p.get("fish", 0))
	var algae: int = int(p.get("algae", 0))
	var mf: int = int(p.get("max_fish", 0))
	var ma: int = int(p.get("max_algae", 0))

	return "[Population]\nfish: %d / %d\nalgae: %d / %d\n" % [fish, mf, algae, ma]



# ============================================================
# Layer Applied（惯性后的真实值）
# ============================================================

func _format_layer_applied_block(layer_index: int) -> String:
	var layers := get_tree().get_nodes_in_group("layers")
	if layers.is_empty():
		return "[Layer Applied]\n(no layers)\n"

	var layer_node: Node = null
	if layer_index >= 0 and layer_index < layers.size():
		layer_node = layers[layer_index]

	if layer_node == null:
		return "[Layer Applied]\n(layer not found)\n"

	if not ("state" in layer_node):
		return "[Layer Applied]\n(no state)\n"

	var ls = layer_node.state
	if ls == null:
		return "[Layer Applied]\n(state null)\n"

	var applied: Dictionary = ls.applied
	var taus: Dictionary = ls.taus

	if applied.is_empty():
		return "[Layer Applied]\n(empty)\n"

	var s := ""
	s += "[Layer Applied]\n"
	s += "name: %s\n" % String(ls.name)
	s += "dt: %.3f\n" % float(ls.dt)

	# 只显示关键字段（与你当前生态一致）
	var keys := [
		"spawn.fish_bias",
		"spawn.algae_bias",
		"death.fish_bias",
		"invasion.risk",
		"budget.spawn_points",
		"env.pollution",
	]

	for k in keys:
		var v := float(applied.get(k, 0.0))
		var tau := float(taus.get(k, 0.0))
		if tau > 0.0:
			s += "%s: %.2f  (tau=%.1f)\n" % [k, v, tau]
		else:
			s += "%s: %.2f\n" % [k, v]

	return s

# ============================================================
# 工具：限制行数（防止刷屏）
# ============================================================

func _limit_lines(text: String, max_lines: int) -> String:
	var lines := text.split("\n")
	if lines.size() <= max_lines:
		return text
	return "\n".join(lines.slice(0, max_lines))
