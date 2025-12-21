# ============================================================
# 模块宪法：layers/common/layer_warning_vignette.gd
# ============================================================
#
# LayerWarningVignette
# - 专职“危险边缘提示”
# - 不做全屏染色
# - 不影响亮度/颜色主调
#
# 输入（只读）：
# - parent.state.applied["invasion.risk"]
#
# 输出：
# - 屏幕边缘红色 vignette
# - 风险高时轻微呼吸/闪烁
#
# ============================================================
extends Node
class_name LayerWarningVignette
# ------------------------------------------------------------
# 模块：layers/common/layer_warning_vignette.gd
# 职责：只读“风险警示遮罩”(Vignette)。
# 输入：父 LayerBase 的 state.applied（只读）
# 输出：只修改一个 ColorRect（Vignette）的颜色 alpha
#
# 原则：
# - 黑盒：不依赖 WorldRoot，不改生态，不改 Layer state，只读 applied。
# - 可开关：enabled=false 时效果淡出归零。
# - 默认安全：找不到节点/数据时，自动淡出到透明。
# ------------------------------------------------------------

@export var enabled: bool = true

# ✅ 用 NodePath（Godot 4 的 get_node_or_null 需要它）
# 你的层级里 Vignette 是同层的兄弟节点，所以默认 "../Vignette"（父节点下找）
# 如果你的脚本挂在 Layer 节点的子节点（比如 WarningVignette），那就用 "../Vignette"
@export var vignette_path: NodePath = NodePath("../Vignette")

# 视觉参数
@export var tau_visual: float = 1.2
@export var risk_to_alpha: float = 0.55
@export var max_alpha: float = 0.60

# 呼吸脉冲（可选）
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 1.2
@export var pulse_strength: float = 0.08

var _vignette: ColorRect = null
var _risk_v: float = 0.0
var _pulse_t: float = 0.0

func _ready() -> void:
	# 直接用 NodePath 找节点（更稳）
	_vignette = get_node_or_null(vignette_path) as ColorRect

	if _vignette == null:
		push_warning("LayerWarningVignette: Vignette ColorRect not found at path: %s" % String(vignette_path))
		return

	# 强制初始化为透明黑，避免 Inspector 手动设成红导致整屏红
	_vignette.color = Color(0.0, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	if _vignette == null:
		return

	# 总开关：关闭就淡出
	if not enabled:
		_fade_out(dt)
		return

	var layer := get_parent()
	if layer == null or not ("state" in layer):
		_fade_out(dt)
		return

	var s = layer.state
	if s == null:
		_fade_out(dt)
		return

	var applied: Dictionary = s.applied
	if applied.is_empty():
		_fade_out(dt)
		return

	# 只读风险值：invasion.risk
	var risk := float(applied.get("invasion.risk", 0.0))
	risk = clampf(risk, 0.0, 1.0)

	# 平滑
	_risk_v = _exp_smooth(_risk_v, risk, dt, tau_visual)

	# 脉冲（可选）
	var pulse := 0.0
	if pulse_enabled:
		_pulse_t += dt * pulse_speed
		pulse = (sin(_pulse_t * TAU) * 0.5 + 0.5) * pulse_strength

	# 最终 alpha（只改 alpha，不改颜色为红！）
	var a := clampf(_risk_v * risk_to_alpha + pulse, 0.0, max_alpha)
	_vignette.color = Color(0.0, 0.0, 0.0, a)

func _fade_out(dt: float) -> void:
	_risk_v = _exp_smooth(_risk_v, 0.0, dt, tau_visual)
	var a := clampf(_risk_v * risk_to_alpha, 0.0, max_alpha)
	_vignette.color = Color(0.0, 0.0, 0.0, a)

func _exp_smooth(cur: float, target: float, dt: float, tau: float) -> float:
	if tau <= 0.0001:
		return target
	var k := 1.0 - exp(-dt / tau)
	return cur + (target - cur) * k
