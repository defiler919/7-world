extends Node
class_name LayerHazard

# ============================================================
# LayerHazard（黑盒）
# ------------------------------------------------------------
# 输入：父节点 layer.state.applied（只读）
# 输出：写入 layer.state.metrics（只写派生指标）
#
# 目的：
# - 把多个生态字段融合成一个“危险度 hazard_level”
# - 让后续系统（AI、事件、音效、UI）有统一的可订阅指标
# - 不直接改生态/不直接控制生成/不直接画面
# ============================================================

@export var tau_hazard: float = 3.0     # 危险度滤波时间常数（越大越慢）
@export var enabled: bool = true

# 内部平滑后的 hazard 值（0~1）
var _hazard_v: float = 0.0

func _process(dt: float) -> void:
	if not enabled:
		return

	var layer := get_parent()
	if layer == null or not ("state" in layer):
		return

	var s = layer.state
	if s == null:
		return

	var applied: Dictionary = s.applied
	if applied.is_empty():
		return

	# --- 1) 取输入（只读） ---
	var invasion: float = float(applied.get("invasion.risk", 0.0))          # 0~1
	var pollution: float = float(applied.get("env.pollution", 0.0))         # 可能 0~几十
	var death_fish: float = float(applied.get("death.fish_bias", 0.0))      # 0~1（或更小）

	# --- 2) 归一化/映射（关键：把不同量纲揉成 0~1） ---
	# pollution 你现在会涨到 40+，这里用一个“软饱和”映射：
	# x/(x+k)  -> 0..1，且越到后面越慢
	var pol01 := _soft01(pollution, 10.0)  # k=10：pollution=10 -> 0.5，20->0.67，40->0.8
	var inv01 := clampf(invasion, 0.0, 1.0)
	var death01 := clampf(death_fish, 0.0, 1.0)

	# --- 3) 融合：hazard_target（0~1） ---
	# 权重可以以后调；现在先给一个直觉合理的组合：
	# 入侵（主） + 污染（次） + 死亡倾向（少量）
	var hazard_target := clampf(inv01 * 0.55 + pol01 * 0.35 + death01 * 0.10, 0.0, 1.0)

	# --- 4) 平滑（避免抖动） ---
	_hazard_v = _exp_smooth(_hazard_v, hazard_target, dt, tau_hazard)

	# --- 5) 输出：只写 metrics（不动其他） ---
	if s.metrics == null:
		s.metrics = {}

	s.metrics["hazard.target"] = hazard_target
	s.metrics["hazard.value"] = _hazard_v
	s.metrics["hazard.invasion01"] = inv01
	s.metrics["hazard.pollution01"] = pol01
	s.metrics["hazard.death01"] = death01


# --- 工具：指数平滑 ---
func _exp_smooth(cur: float, target: float, dt: float, tau: float) -> float:
	if tau <= 0.0001:
		return target
	var k := 1.0 - exp(-dt / tau)
	return cur + (target - cur) * k

# --- 工具：软饱和映射到 0..1 ---
func _soft01(x: float, k: float) -> float:
	x = maxf(0.0, x)
	k = maxf(0.0001, k)
	return x / (x + k)
