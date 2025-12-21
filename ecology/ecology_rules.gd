# ============================================================
# 模块宪法：ecology/ecology_rules.gd — Intent 输出接口
# ============================================================
# 【核心定位】
# EcologyRules 是“生态建议引擎（Advisor）”
# - 输入：WorldRoot / EcologyLayerState / WorldClock
# - 输出：Intent（建议/倾向参数 Dictionary）

# 〖核心定位〗
# EcologyRules 是“生态建议引擎（Advisor）”
# - 输入：WorldRoot / EcologyLayerState / WorldClock
# - 输出：Intent（建议/倾向参数 Dictionary）
#
# 〖一句话〗
# 只回答“更倾向于发生什么？”
# ❌ 不直接生成/删除/移动任何节点，不改相机，不改 WorldState
#
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
# 你项目里已有 EcologyLayerState Resource（至少包含 fish / algae / pollution）
var layer_states: Array = []  # Array[EcologyLayerState]

# 每层的“额外元数据”（不写进 Resource，避免你再遇到字段不存在报错）
var _meta: Array[Dictionary] = []

# ------------------------------------------------------------
# Intent 快照（对外只读输出）
# ------------------------------------------------------------
var _layer_intents: Array[Dictionary] = []
var _intent_version: int = 0

# ------------------------------------------------------------
# 全局随机源（事件触发）
# ------------------------------------------------------------
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------
# （可调）生态长期稳定参数（重点：避免末日）
# ------------------------------------------------------------
@export var fish_cap_default: float = 50.0
@export var algae_cap_default: float = 80.0

# 藻类“目标密度”（类似环境承载的自然回归点），会向这个值回归
@export var algae_target_ratio: float = 0.35  # 0.35 * algae_cap

# 污染：产生 vs 净化（净化随藻类增长）
@export var pollution_base_prod: float = 0.02          # 每秒基础产生
@export var pollution_prod_per_fish: float = 0.003     # 鱼越多产生越多
@export var pollution_natural_decay: float = 0.010     # 每秒基础净化
@export var pollution_decay_per_algae: float = 0.0009  # 藻越多净化越强
@export var pollution_soft_cap: float = 300.0          # 软上限：极端情况下也别爆到无限大

# 鱼：增长/死亡（污染影响死亡，藻类提供增长）
@export var fish_growth_per_algae: float = 0.010       # 鱼增长 ~ algae * k
@export var fish_natural_death: float = 0.004          # 基础死亡
@export var fish_death_per_pollution: float = 0.0009   # 污染导致死亡（线性）

# ------------------------------------------------------------
# （可调）危机事件系统（触发—持续—结束—恢复）
# ------------------------------------------------------------
@export var crisis_min_duration: float = 18.0
@export var crisis_max_duration: float = 45.0
@export var crisis_min_cooldown: float = 35.0
@export var crisis_max_cooldown: float = 90.0

# 危机触发：基于 risk 的概率（每秒一次抽奖）
@export var crisis_base_chance_per_sec: float = 0.002  # 0.2%/秒（很低）
@export var crisis_risk_chance_scale: float = 0.010    # risk=1 时额外 1.0%/秒

# 危机对生态的冲击强度（不会一次打穿）
@export var crisis_fish_shock_min: float = 0.15
@export var crisis_fish_shock_max: float = 0.45
@export var crisis_pollution_spike_min: float = 1.0
@export var crisis_pollution_spike_max: float = 6.0

# 危机期间持续伤害/持续污染
@export var crisis_fish_dps: float = 0.006         # 每秒额外损失比例（乘 fish）
@export var crisis_pollution_dps: float = 0.06     # 每秒额外污染

# 恢复加速（危机结束后的一段时间）
@export var recover_boost_time: float = 40.0
@export var recover_pollution_decay_boost: float = 0.025
@export var recover_fish_growth_boost: float = 0.008

# 风险值：由污染+生态健康+危机状态得出（并带缓慢回落）
@export var risk_pollution_k: float = 0.010
@export var risk_low_algae_k: float = 0.40
@export var risk_crisis_bonus: float = 0.35
@export var risk_recover_bonus: float = -0.25
@export var risk_tau: float = 12.0  # 风险惯性（越大变化越慢）

# ------------------------------------------------------------
# 初始化
# ------------------------------------------------------------
func _ready() -> void:
	_rng.randomize()

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
	_meta.clear()

	for i in range(layer_count):
		var s := EcologyLayerState.new()
		# 初始给点差异，便于肉眼验证
		s.fish = 10.0 + i * 2.0
		s.algae = 20.0 + i * 5.0
		s.pollution = 0.0
		layer_states.append(s)

		_meta.append({
			"risk": 0.0,
			"crisis_left": 0.0,
			"cooldown_left": float(_rng.randf_range(10.0, 25.0)), # 开局先别立刻触发
			"recover_left": 0.0,
			"last_event": "",
		})

# ------------------------------------------------------------
# 初始化 intent 容器
# ------------------------------------------------------------
func _init_intents(layer_count: int) -> void:
	_layer_intents.clear()
	for _i in range(layer_count):
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
func _on_tick_1s(world_time: float, _tick_index: int) -> void:
	for i in range(layer_states.size()):
		_step_layer(i, 1.0)

	_rebuild_intents(world_time)

# ------------------------------------------------------------
# 生态内部规则（事实更新）
# ------------------------------------------------------------
func _step_layer(layer_index: int, dt: float) -> void:
	var s = layer_states[layer_index]
	var m: Dictionary = _meta[layer_index]

	# -------- 1) 危机计时推进 --------
	if m["cooldown_left"] > 0.0:
		m["cooldown_left"] = maxf(0.0, float(m["cooldown_left"]) - dt)

	var in_crisis: bool = float(m["crisis_left"]) > 0.0
	if in_crisis:
		m["crisis_left"] = maxf(0.0, float(m["crisis_left"]) - dt)
		# 危机期间：持续伤害 & 持续污染
		var fish_loss :float = s.fish * crisis_fish_dps * dt
		s.fish -= fish_loss
		s.pollution += crisis_pollution_dps * dt

		# 危机结束瞬间：进入恢复期
		if float(m["crisis_left"]) <= 0.0:
			m["recover_left"] = recover_boost_time
			m["last_event"] = "crisis_end"

	# 恢复计时推进
	if float(m["recover_left"]) > 0.0:
		m["recover_left"] = maxf(0.0, float(m["recover_left"]) - dt)

	# -------- 2) 污染：产生 vs 净化（长期稳定关键） --------
	# 产生：基础 + 与鱼相关
	var prod :float = pollution_base_prod + (s.fish * pollution_prod_per_fish)
	# 净化：基础 + 与藻类相关；恢复期额外加速
	var decay :float = pollution_natural_decay + (s.algae * pollution_decay_per_algae)
	if float(m["recover_left"]) > 0.0:
		decay += recover_pollution_decay_boost

	s.pollution += (prod - decay) * dt
	s.pollution = clampf(s.pollution, 0.0, pollution_soft_cap)

	# -------- 3) 藻类：自愈回归（你想要“水草自适应数量”） --------
	# 向目标密度回归（类似 logistic / 回归力），污染抑制但不会死绝（除非你自己想）
	var algae_cap := algae_cap_default
	var algae_target := algae_cap * algae_target_ratio

	# 回归力：偏离目标越多，回归越快；同时受污染抑制
	var algae_return :float = (algae_target - s.algae) * 0.020
	var algae_pollution_penalty :float = s.pollution * 0.0020
	s.algae += (algae_return - algae_pollution_penalty) * dt

	# 强制“只要还有一点，就能慢慢回升”
	if s.algae < 0.5:
		s.algae = 0.5

	s.algae = clampf(s.algae, 0.0, algae_cap)

	# -------- 4) 鱼：依赖藻类的增长 + 自然死亡 + 污染死亡 --------
	var growth :float = s.algae * fish_growth_per_algae
	if float(m["recover_left"]) > 0.0:
		growth += recover_fish_growth_boost

	var death :float = (s.fish * fish_natural_death) + (s.fish * s.pollution * fish_death_per_pollution)
	s.fish += (growth - death) * dt

	# 只要藻类存在，鱼不会“永远归零”（慢慢回来）
	if s.fish < 0.0:
		s.fish = 0.0
	if s.fish == 0.0 and s.algae > 1.0:
		# 给一个极小的“回归种群”，让系统能复苏
		s.fish = 0.2

	s.fish = clampf(s.fish, 0.0, fish_cap_default)

	# -------- 5) 风险 risk：污染 + 生态健康 + 状态加成（并带惯性） --------
	var algae_health := clampf(s.algae / algae_cap_default, 0.0, 1.0)
	var poll_term := clampf(s.pollution * risk_pollution_k, 0.0, 1.0)
	var low_algae_term := clampf((1.0 - algae_health) * risk_low_algae_k, 0.0, 1.0)

	var target_risk := poll_term + low_algae_term
	if in_crisis:
		target_risk += risk_crisis_bonus
	if float(m["recover_left"]) > 0.0:
		target_risk += risk_recover_bonus

	target_risk = clampf(target_risk, 0.0, 1.0)

	# 一阶惯性：risk_tau 秒时间常数
	var cur_risk: float = float(m["risk"])
	var k := 1.0 - exp(-dt / maxf(0.001, risk_tau))
	cur_risk = cur_risk + (target_risk - cur_risk) * k
	m["risk"] = clampf(cur_risk, 0.0, 1.0)

	# -------- 6) 是否触发危机（事件） --------
	# 只在不处于危机、冷却结束时抽奖
	if (not in_crisis) and float(m["cooldown_left"]) <= 0.0:
		var chance := crisis_base_chance_per_sec + float(m["risk"]) * crisis_risk_chance_scale
		if _rng.randf() < chance:
			_start_crisis(layer_index)

	_meta[layer_index] = m

func _start_crisis(layer_index: int) -> void:
	var s = layer_states[layer_index]
	var m: Dictionary = _meta[layer_index]

	# 设置危机持续时间 + 冷却
	var dur := _rng.randf_range(crisis_min_duration, crisis_max_duration)
	m["crisis_left"] = dur
	m["cooldown_left"] = _rng.randf_range(crisis_min_cooldown, crisis_max_cooldown)
	m["recover_left"] = 0.0
	m["last_event"] = "crisis_start"

	# 立即冲击：鱼损失一部分 + 污染跳升一点（不会无限）
	var shock_ratio := _rng.randf_range(crisis_fish_shock_min, crisis_fish_shock_max)
	s.fish *= (1.0 - shock_ratio)

	var spike := _rng.randf_range(crisis_pollution_spike_min, crisis_pollution_spike_max)
	s.pollution = clampf(s.pollution + spike, 0.0, pollution_soft_cap)

	# （可选）层间“收益/损失”雏形：浅海(0)危机时，深海(1)稍微获益
	# 这只是“机制接口”，你以后可以换成更具体的“深海入侵”事件类型。
	if layer_states.size() >= 2 and layer_index == 0:
		var deep = layer_states[1]
		deep.fish = clampf(deep.fish + shock_ratio * 2.0, 0.0, fish_cap_default)

	_meta[layer_index] = m

# ------------------------------------------------------------
# Intent 重建（对外建议）
# ------------------------------------------------------------
func _rebuild_intents(world_time: float) -> void:
	_intent_version += 1

	for i in range(layer_states.size()):
		var s = layer_states[i]
		var m: Dictionary = _meta[i]

		var risk: float = float(m["risk"])
		var in_crisis: bool = float(m["crisis_left"]) > 0.0

		# spawn 倾向：藻/鱼越少越希望补，污染越高越抑制
		var algae_need := clampf(1.0 - (s.algae / algae_cap_default), 0.0, 1.0)
		var fish_need := clampf(1.0 - (s.fish / fish_cap_default), 0.0, 1.0)

		var spawn_algae := clampf(0.8 + algae_need * 1.2 - s.pollution * 0.01, 0.0, 2.0)
		var spawn_fish := clampf(0.6 + fish_need * 1.4 - s.pollution * 0.008, 0.0, 2.0)

		# death 倾向：污染高 + 危机中更高
		var death_fish := clampf(s.pollution * 0.004 + (0.25 if in_crisis else 0.0), 0.0, 1.0)

		# budget：污染高/危机中，预算更紧（但保底不为 0）
		var budget :float = 2.8 - s.pollution * 0.01 - (0.6 if in_crisis else 0.0)
		budget = clampf(budget, 0.6, 5.0)

		var intent: Dictionary = {
			# ---- 固定字段 ----
			"version": _intent_version,
			"world_time": world_time,
			"layer_index": i,

			# ---- 生成倾向（建议值）----
			"spawn.fish_bias": spawn_fish,
			"spawn.algae_bias": spawn_algae,

			# ---- 死亡 / 衰退（建议值）----
			"death.fish_bias": death_fish,

			# ---- 入侵风险（建议值）----
			"invasion.risk": risk,

			# ---- 执行预算（建议值）----
			"budget.spawn_points": budget,

			# ---- 环境只读（事实快照）----
			"env.pollution": s.pollution,

			# ---- Debug ----
			"debug.crisis_left": float(m["crisis_left"]),
			"debug.cooldown_left": float(m["cooldown_left"]),
			"debug.recover_left": float(m["recover_left"]),
			"debug.last_event": String(m["last_event"]),
		}

		_layer_intents[i] = intent

# ------------------------------------------------------------
# ===== 对外只读接口（Intent 宪法）=====
# ------------------------------------------------------------

# A. 获取某一层的 intent（永远返回 Dictionary；越界返回 {}）
func get_layer_intent(layer_index: int) -> Dictionary:
	if layer_index < 0 or layer_index >= _layer_intents.size():
		return {}
	var intent := _layer_intents[layer_index].duplicate(true)
	intent["version"] = _intent_version
	intent["source"] = "ecology_rules"
	return intent

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

# Debug / 观察用（事实）
func get_layer_state(layer_index: int):
	if layer_index < 0 or layer_index >= layer_states.size():
		return null
	return layer_states[layer_index]
