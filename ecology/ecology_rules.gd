# ============================================================
# 模块宪法：ecology/ecology_rules.gd — Intent 输出接口
# ============================================================
# 【核心定位】
# EcologyRules 是“生态建议引擎（Advisor）”
# - 输入：WorldRoot / EcologyLayerState / WorldClock
# - 输出：Intent（建议/倾向参数 Dictionary）
#
# 【一句话】
# 👉 只回答“更倾向于发生什么？”
# ❌ 不直接生成/删除/移动任何节点，不改相机，不改 WorldState
# ============================================================

extends Node
class_name EcologyRules

# ------------------------------------------------------------
# 外部依赖（路径注入：Inspector 填）
# ------------------------------------------------------------
@export var world_root_path: NodePath
@export var clock_path: NodePath

var world_root: Node
var clock: WorldClock

# ------------------------------------------------------------
# 内部状态（生态“事实”）
# ------------------------------------------------------------
var layer_states: Array[EcologyLayerState] = []

# ------------------------------------------------------------
# Intent 快照（对外只读输出）
# ------------------------------------------------------------
var _layer_intents: Array[Dictionary] = []
var _intent_version: int = 0

# ------------------------------------------------------------
# 初始化
# ------------------------------------------------------------
func _ready() -> void:
	world_root = get_node_or_null(world_root_path)
	clock = get_node_or_null(clock_path) as WorldClock

	if world_root == null:
		push_error("EcologyRules: world_root_path not found.")
		return
	if clock == null:
		push_error("EcologyRules: clock_path not found.")
		return
	if not ("config" in world_root) or world_root.config == null:
		push_error("EcologyRules: WorldRoot.config missing.")
		return

	var layer_count: int = world_root.config.layer_count()
	_init_states(layer_count)
	_init_intents(layer_count)

	# 接入 WorldClock：tick_1s(world_time: float, tick_index: int)
	if clock.has_signal("tick_1s"):
		clock.tick_1s.connect(_on_tick_1s)
	else:
		# 极端兜底：如果没有信号就用 _process 每秒跑一次
		set_process(true)

# ------------------------------------------------------------
# 初始化生态状态（事实）
# ------------------------------------------------------------
func _init_states(layer_count: int) -> void:
	layer_states.clear()
	for i in range(layer_count):
		var s := EcologyLayerState.new()
		# 给每层一点差异，便于肉眼验证
		s.fish = 10.0 + i * 2.0
		s.algae = 20.0 + i * 5.0
		s.pollution = 0.0
		layer_states.append(s)

# ------------------------------------------------------------
# 初始化 intent 容器
# ------------------------------------------------------------
func _init_intents(layer_count: int) -> void:
	_layer_intents.clear()
	for i in range(layer_count):
		_layer_intents.append({})

# ------------------------------------------------------------
# tick 驱动兜底（只有在 clock 没信号时才用）
# ------------------------------------------------------------
var _accum := 0.0
func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 1.0:
		_accum -= 1.0
		_on_tick_1s(0.0, 0)

# ------------------------------------------------------------
# 每秒 tick：先更新事实，再生成 intent
# ------------------------------------------------------------
func _on_tick_1s(world_time: float, tick_index: int) -> void:
	for i in range(layer_states.size()):
		_step_layer(layer_states[i])

	_rebuild_intents(world_time)

# ------------------------------------------------------------
# 生态内部规则（事实更新）
# ------------------------------------------------------------
func _step_layer(s: EcologyLayerState) -> void:
	# 藻类增长（污染抑制）
	s.algae += max(0.0, 1.5 - s.pollution * 0.05)

	# 鱼依赖藻类，但污染致死
	s.fish += (s.algae * 0.02) - (s.pollution * 0.03)

	# 污染缓慢累积
	s.pollution += 0.2

	# clamp
	s.fish = max(0.0, s.fish)
	s.algae = max(0.0, s.algae)
	s.pollution = max(0.0, s.pollution)

# ------------------------------------------------------------
# Intent 重建（对外建议）
# - 注意：Dictionary 里不要放 null（新手期最省事）
# ------------------------------------------------------------
func _rebuild_intents(world_time: float) -> void:
	_intent_version += 1

	for i in range(layer_states.size()):
		var s := layer_states[i]

		var note: String = "pollution rising" if s.pollution > 8.0 else ""

		var intent: Dictionary = {
			# ---- 固定字段 ----
			"version": _intent_version,
			"world_time": world_time,
			"layer_index": i,

			# ---- 生成倾向（建议值）----
			"spawn.fish_bias": clamp(s.algae / 50.0, 0.0, 2.0),
			"spawn.algae_bias": clamp(1.2 - s.pollution * 0.05, 0.0, 2.0),

			# ---- 死亡 / 衰退（建议值）----
			"death.fish_bias": clamp(s.pollution * 0.02, 0.0, 1.0),

			# ---- 入侵风险（建议值）----
			"invasion.risk": clamp(s.pollution / 30.0, 0.0, 1.0),

			# ---- 执行预算（建议值）----
			"budget.spawn_points": clamp(3.0 - s.pollution * 0.1, 0.0, 5.0),

			# ---- 环境只读（事实快照）----
			"env.pollution": s.pollution,

			# ---- Debug ----
			"debug.note": note
		}

		_layer_intents[i] = intent

# ------------------------------------------------------------
# ===== 对外只读接口（Intent 宪法）=====
# ------------------------------------------------------------

# A. 获取某一层的 intent（永远返回 Dictionary；越界返回 {}）
func get_layer_intent(layer_index: int) -> Dictionary:
	if layer_index < 0 or layer_index >= _layer_intents.size():
		return {}
	return _layer_intents[layer_index]

# B. 获取全局 intent（可选占位）
func get_world_intent() -> Dictionary:
	var t: float = 0.0
	if clock != null:
		t = clock.world_time
	return {
		"version": _intent_version,
		"world_time": t
	}

# C. intent 版本号
func get_intent_version() -> int:
	return _intent_version

# ------------------------------------------------------------
# Debug / 观察用（事实）
# （这里不写返回类型，允许返回 null，避免你再被类型系统卡住）
# ------------------------------------------------------------
func get_layer_state(layer_index: int):
	if layer_index < 0 or layer_index >= layer_states.size():
		return null
	return layer_states[layer_index]
