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

var world_root: Node = null
var ecology_rules: Node = null

@onready var label := Label.new()

func _ready() -> void:
	# 依赖注入：通过 Inspector 填 NodePath
	world_root = get_node_or_null(world_root_path)
	if world_root == null:
		push_error("DebugOverlay: world_root_path not found.")
		return

	ecology_rules = get_node_or_null(ecology_rules_path)
	if ecology_rules == null:
		# 允许为空：只是少一块生态显示
		push_warning("DebugOverlay: ecology_rules_path not found. (Ecology section disabled)")

	# Label 初始化
	label.name = "DebugLabel"
	label.position = Vector2(12, 12)
	label.text = "[World Debug]\n(waiting...)"
	add_child(label)

func _process(_delta: float) -> void:
	if world_root == null:
		return
	if not world_root.has_method("get_world_state"):
		return

	var state = world_root.get_world_state()
	if state == null:
		return

	label.text = _format_state_and_ecology(state)

# ------------------------------------------------------------
# 格式化：WorldState + Ecology Intent
# ------------------------------------------------------------
func _format_state_and_ecology(state) -> String:
	var text := ""
	text += "[World Debug]\n"
	text += "Layer: %d\n" % int(state.current_layer_index)
	text += "Col: %d\n" % int(state.current_col_index)
	text += "Camera Center: (%.1f, %.1f)\n" % [state.camera_center.x, state.camera_center.y]
	text += "Local Offset: (%.1f, %.1f)\n" % [state.camera_local_offset.x, state.camera_local_offset.y]
	text += "Viewport: %.0f x %.0f\n" % [state.viewport_size.x, state.viewport_size.y]
	text += "Cooldown: %.2f\n" % float(state.switch_cooldown_left)
	text += "World Time: %.2f\n" % float(state.world_time)

	# --- Ecology Intent（只读附加块） ---
	text += "\n"
	text += _format_ecology_intent_block(int(state.current_layer_index))

	return text

func _format_ecology_intent_block(layer_index: int) -> String:
	# 生态系统不存在/没挂上 → 给提示但不报错
	if ecology_rules == null:
		return "[Ecology Intent]\n(not connected)\n"

	# EcologyRules 必须提供 get_layer_intent(layer_index)
	if not ecology_rules.has_method("get_layer_intent"):
		return "[Ecology Intent]\n(no get_layer_intent)\n"

	var intent: Dictionary = ecology_rules.get_layer_intent(layer_index)
	if intent.is_empty():
		return "[Ecology Intent]\n(empty)\n"

	# 尽量只显示“关键字段”，避免刷屏
	var v := int(intent.get("version", 0))
	var t := float(intent.get("world_time", 0.0))

	var fish_bias := float(intent.get("spawn.fish_bias", 0.0))
	var algae_bias := float(intent.get("spawn.algae_bias", 0.0))
	var death_fish := float(intent.get("death.fish_bias", 0.0))
	var invasion := float(intent.get("invasion.risk", 0.0))
	var budget := float(intent.get("budget.spawn_points", 0.0))
	var pollution := float(intent.get("env.pollution", 0.0))

	var s := ""
	s += "[Ecology Intent]\n"
	s += "version: %d  time: %.2f\n" % [v, t]
	s += "spawn.fish_bias: %.2f\n" % fish_bias
	s += "spawn.algae_bias: %.2f\n" % algae_bias
	s += "death.fish_bias: %.2f\n" % death_fish
	s += "invasion.risk: %.2f\n" % invasion
	s += "budget.spawn_points: %.2f\n" % budget
	s += "env.pollution: %.2f\n" % pollution
	return s
