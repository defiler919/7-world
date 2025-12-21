extends Resource
class_name LayerState

# 本层名字（用于 debug）
var name: StringName = &""

# 本帧 dt（debug/推导用）
var dt: float = 0.0

# 原始 intent（生态给的建议值，未滤波）
var intent: Dictionary = {}

# applied（惯性滤波后的“本层真正采用值”）
var applied: Dictionary = {}

# 每个 key 使用的 tau（debug 用）
var taus: Dictionary = {}

# ===== Day7 新增：metrics（只写“派生指标”，不参与决策）=====
# 例：hazard_level / danger / clarity / etc.
var metrics: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"name": String(name),
		"intent": intent,
		"applied": applied,
		"taus": taus,
		"dt": dt
	}
