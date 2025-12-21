# ============================================================
# 模块宪法：layers/common/layer_visuals.gd
# ============================================================
#
# LayerVisuals = “层表现驱动器”（Presentation Driver）
#
# 输入（只读）：
# - parent.state.applied（Dictionary）
#   关键字段（不存在时使用默认）：
#     env.pollution
#     invasion.risk
#     budget.spawn_points
#
# 输出（表现）：
# - 控制本层背景的颜色、亮度、危险感叠层等（不改世界逻辑）
#
# 黑盒化：
# - 不引用 EcologyRules
# - 不改 LayerBase / Spawner
# - 只要求父节点有 state.applied
#
# ============================================================

extends Node
class_name LayerVisuals

# 你可以在每层 Inspector 里设置：本层要控制哪个 ColorRect 做“滤镜”
@export var overlay_path: NodePath
# 可选：控制背景（比如 Background ColorRect）
@export var background_path: NodePath

# 映射强度（可调参）
@export var pollution_to_darkness: float = 0.06   # 污染越高越暗
@export var risk_to_warning: float = 0.9          # 风险越高越“危险色”
@export var budget_to_vivid: float = 0.12         # 预算越高越“鲜活”

# 平滑（表现也建议有惯性，避免闪烁）
@export var tau_visual: float = 0.6

var _overlay: CanvasItem = null
var _bg: CanvasItem = null

# 内部状态（表现用，不影响系统）
var _v_dark: float = 0.0
var _v_warn: float = 0.0
var _v_vivid: float = 0.0

func _ready() -> void:
	_overlay = get_node_or_null(overlay_path) as CanvasItem
	_bg = get_node_or_null(background_path) as CanvasItem

func _process(dt: float) -> void:
	var layer: Node = get_parent()
	if layer == null:
		return
	if not ("state" in layer):
		return

	var s = layer.state
	if s == null:
		return

	var applied: Dictionary = s.applied
	if applied.is_empty():
		return

	# ---- 读取 applied（只读）----
	var pollution: float = float(applied.get("env.pollution", 0.0))
	var risk: float = float(applied.get("invasion.risk", 0.0))
	var budget: float = float(applied.get("budget.spawn_points", 0.0))

	# ---- 映射到表现因子（先粗暴映射，后面可微调）----
	# darkness: 0~1
	var t_dark: float = clampf(pollution * pollution_to_darkness, 0.0, 0.85)
	# warning: 0~1
	var t_warn: float = clampf(risk * risk_to_warning, 0.0, 1.0)
	# vivid: 0~1
	var t_vivid: float = clampf(budget * budget_to_vivid, 0.0, 0.6)

	# ---- 表现惯性（避免闪）----
	_v_dark = _exp_smooth(_v_dark, t_dark, dt, tau_visual)
	_v_warn = _exp_smooth(_v_warn, t_warn, dt, tau_visual)
	_v_vivid = _exp_smooth(_v_vivid, t_vivid, dt, tau_visual)

	_apply_visuals()

func _apply_visuals() -> void:
	# 1) Overlay：只负责“暗化”（污染），颜色保持黑色
	#    危险感（risk）这里只做非常轻微的偏色（不会染红全屏）
	if _overlay != null:
		var dark_alpha: float = _v_dark

		if _overlay is ColorRect:
			var cr := _overlay as ColorRect
			# 纯黑暗化层：污染越高 alpha 越高
			cr.color = Color(0.0, 0.0, 0.0, dark_alpha)

		# 风险偏色：只做很轻微的 tint（不改变 alpha）
		# 这样不会出现“越变越红”的覆盖问题
		var warn_k: float = _v_warn
		_overlay.modulate = Color(
			1.0 + 0.12 * warn_k,   # 红轻微增
			1.0 - 0.05 * warn_k,   # 绿轻微减
			1.0 - 0.05 * warn_k,   # 蓝轻微减
			1.0
		)

	# 2) 背景“鲜活度”：预算越高越亮一点（轻微）
	if _bg != null:
		var k: float = _v_vivid
		_bg.modulate = Color(1.0 + k, 1.0 + k, 1.0 + k, 1.0)


func _exp_smooth(cur: float, target: float, dt: float, tau: float) -> float:
	if tau <= 0.0001:
		return target
	var a: float = 1.0 - exp(-dt / tau)
	return cur + (target - cur) * a
