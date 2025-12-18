# ============================================================
# 模块宪法：debug/debug_overlay.gd
# ============================================================
#
# 【这个模块是什么？】
# DebugOverlay 是一个“只读调试显示层（Observer）”
#
# 它的唯一职责是：
# 👉 把世界当前的【状态（State）】和【生态建议（Intent）】
#    以人类可读的方式显示在屏幕上。
#
# ------------------------------------------------------------
# 【它负责什么？】
# 1. 从 WorldRoot 读取 WorldState（只读）
# 2. 从 EcologyRules 读取 Intent（只读）
# 3. 把这些数据格式化为文本
# 4. 固定显示在屏幕左上角
#
# ------------------------------------------------------------
# 【它不负责什么（非常重要）】
# ❌ 不修改任何状态
# ❌ 不参与生态计算
# ❌ 不驱动相机 / 切层 / 输入
# ❌ 不产生任何游戏行为
#
# DebugOverlay 永远只是：
# 👉 观察者（Observer）
#
# ------------------------------------------------------------
# 【设计原则】
# - 任何字段都允许“读不到”
# - 任何模块缺失都不会导致游戏崩溃
# - DebugOverlay 可以被整体删除而不影响游戏
#
# ------------------------------------------------------------
# 【为什么用 CanvasLayer？】
# - 不受 Camera2D 影响
# - 相机怎么动，调试信息都固定在屏幕上
#
# ============================================================

extends CanvasLayer

# ------------------------------------------------------------
# 外部依赖（全部通过 Inspector 注入）
# ------------------------------------------------------------

# WorldRoot：提供 get_world_state()
@export var world_root_path: NodePath

# EcologyRules：提供 get_layer_intent()
@export var ecology_rules_path: NodePath


# ------------------------------------------------------------
# 运行时引用（全部允许为空）
# ------------------------------------------------------------

var world_root: Node = null
var ecology_rules: Node = null


# ------------------------------------------------------------
# UI
# ------------------------------------------------------------

@onready var label := Label.new()


# ------------------------------------------------------------
# 生命周期：初始化
# ------------------------------------------------------------

func _ready() -> void:
	# 获取 WorldRoot
	world_root = get_node_or_null(world_root_path)
	if world_root == null:
		push_error("DebugOverlay: world_root_path not found.")

	# 获取 EcologyRules
	ecology_rules = get_node_or_null(ecology_rules_path)
	if ecology_rules == null:
		push_warning("DebugOverlay: ecology_rules_path not found (Intent will be empty).")

	# 初始化 Label
	label.name = "DebugLabel"
	label.position = Vector2(12, 12)
	label.text = "[World Debug]\n(waiting...)"
	add_child(label)


# ------------------------------------------------------------
# 每帧刷新显示（只读）
# ------------------------------------------------------------

func _process(_delta: float) -> void:
	if world_root == null:
		return
	if not world_root.has_method("get_world_state"):
		return

	var state = world_root.get_world_state()
	if state == null:
		return

	label.text = _build_debug_text(state)


# ------------------------------------------------------------
# 内部：构建调试文本
# ------------------------------------------------------------

func _build_debug_text(state) -> String:
	var text := ""

	# =========================
	# World State
	# =========================
	text += "[World State]\n"
	text += "Layer: %d\n" % state.current_layer_index
	text += "Col: %d\n" % state.current_col_index
	text += "World Time: %.2f\n" % state.world_time
	text += "\n"

	# =========================
	# Camera
	# =========================
	text += "[Camera]\n"
	text += "Center: (%.1f, %.1f)\n" % [
		state.camera_center.x,
		state.camera_center.y
	]
	text += "Local Offset: (%.1f, %.1f)\n" % [
		state.camera_local_offset.x,
		state.camera_local_offset.y
	]
	text += "Viewport: %.0f x %.0f\n" % [
		state.viewport_size.x,
		state.viewport_size.y
	]
	text += "Switch Cooldown: %.2f\n" % state.switch_cooldown_left
	text += "\n"

	# =========================
	# Ecology Intent（可选）
	# =========================
	text += "[Ecology Intent]\n"

	if ecology_rules != null and ecology_rules.has_method("get_layer_intent"):
		var intent: Dictionary = ecology_rules.get_layer_intent(state.current_layer_index)

		if intent.is_empty():
			text += "(no intent)\n"
		else:
			text += "spawn.fish_bias: %.2f\n" % float(intent.get("spawn.fish_bias", 0.0))
			text += "spawn.algae_bias: %.2f\n" % float(intent.get("spawn.algae_bias", 0.0))
			text += "death.fish_bias: %.2f\n" % float(intent.get("death.fish_bias", 0.0))
			text += "invasion.risk: %.2f\n" % float(intent.get("invasion.risk", 0.0))
			text += "budget.spawn_points: %.2f\n" % float(intent.get("budget.spawn_points", 0.0))
			text += "env.pollution: %.2f\n" % float(intent.get("env.pollution", 0.0))
	else:
		text += "(EcologyRules not connected)\n"

	return text
