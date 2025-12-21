# ============================================================
# 模块宪法：layers/common/layer_spawner.gd
# ============================================================
#
# 【这个模块是什么？】
# LayerSpawner 是“每层的实体生成/回收控制器”（Spawner / Population Driver）。
#
# 【它的唯一职责是：】
# 👉 读取父层（LayerBase）的只读输出 state.applied，
#    将这些“稳定后的生态参数（Applied）”映射为：
#    - 当前应存在的鱼/藻数量（稳态目标）
#    - 生成（spawn）
#    - 回收（despawn）
#    - 简单死亡（death）
#
# 【它负责什么？】
# 1) 每帧读取父节点的 layer.state.applied（只读）
# 2) 用 applied 计算“目标数量”（target_fish / target_algae）
# 3) 将现存实体数量逼近目标数量（生成/回收）
# 4) 根据 death.* 做最小版死亡（每帧最多杀 1 个，避免抖）
#
# 【它不负责什么？】
# ❌ 不计算 intent（那是 EcologyRules 的职责）
# ❌ 不做惯性（那是 LayerBase + InertiaField 的职责）
# ❌ 不参与 UI / Debug 输出（DebugOverlay 只读）
# ❌ 不依赖具体节点路径（黑盒：只依赖父节点是否有 state）
#
# 【输入（只读）】
# - parent.state.applied: Dictionary
#   关键字段（不存在时取默认）：
#     "budget.spawn_points" : float
#     "spawn.fish_bias"     : float
#     "spawn.algae_bias"    : float
#     "death.fish_bias"     : float
#
# 【输出（行为）】
# - 在父 Layer 节点下 add_child() 实例化 fish/algae
# - 对超量或死亡目标调用 queue_free()
#
# 【黑盒化说明】
# - 你可以把 EcologyRules / LayerBase 完全替换成别的算法，
#   只要最终能产出同样 key 的 applied，这里就继续工作。
# - 你也可以把实体替换成更复杂的鱼群 AI / 贴图 / 动画，
#   只要 fish_scene/algae_scene 仍然是 Node2D（推荐）即可。
#
# ============================================================

extends Node
class_name LayerSpawner

# ------------------------------------------------------------
# 配置：要生成的实体场景（由 Inspector 注入）
# ------------------------------------------------------------
@export var fish_scene: PackedScene
@export var algae_scene: PackedScene

# ------------------------------------------------------------
# 配置：生成区域（相对父 Layer 的局部坐标）
# 说明：这是一个“生成点的随机矩形区域”，不是碰撞区域。
# ------------------------------------------------------------
@export var spawn_rect: Rect2 = Rect2(Vector2(-800, -400), Vector2(1600, 800))

# ------------------------------------------------------------
# 配置：实体数量上限（安全阀，防止 AI/参数爆炸导致失控）
# ------------------------------------------------------------
@export var max_fish: int = 50
@export var max_algae: int = 80

# ------------------------------------------------------------
# 配置：强度缩放（未来调参入口）
# - spawn_rate_scale：当前版本仅预留（你未来可改成“按速率逐渐生成”）
# - death_rate_scale：当前用于死亡概率缩放
# ------------------------------------------------------------
@export var spawn_rate_scale: float = 1.0
@export var death_rate_scale: float = 1.0

# ------------------------------------------------------------
# 内部：记录当前由本 spawner 管理的实体引用
# 注意：我们只存 Node 引用，不存 ID；每帧会清理无效引用。
# ------------------------------------------------------------
var _fish: Array[Node] = []
var _algae: Array[Node] = []


func _ready() -> void:
	# 黑盒要求：这里不依赖外部路径，不强制获取某个节点
	# 只要被挂在某个 Layer 节点下就能工作。
	pass


func _process(dt: float) -> void:
	# --------------------------------------------------------
	# 1) 获取父 Layer，并读取其 state.applied（只读）
	# --------------------------------------------------------
	var layer: Node = get_parent()
	if layer == null:
		return

	# 黑盒约束：不要求父节点必须是某个类，只要它有 state 字段即可
	# ("state" in layer) 是一个很松耦合的检查
	if not ("state" in layer):
		return

	var s = layer.state
	if s == null:
		return

	var applied: Dictionary = s.applied
	if applied.is_empty():
		return

	# --------------------------------------------------------
	# 2) 从 applied 读取关键参数（缺省安全）
	# --------------------------------------------------------
	var budget: float = float(applied.get("budget.spawn_points", 0.0))
	var fish_bias: float = float(applied.get("spawn.fish_bias", 0.0))
	var algae_bias: float = float(applied.get("spawn.algae_bias", 0.0))
	var death_fish: float = float(applied.get("death.fish_bias", 0.0))

	# --------------------------------------------------------
	# 3) 计算目标总量：budget -> target_total
	# 最小版映射：target_total = budget * 10（温和）
	# 注意：这里用 clampf / round 避免 Variant 推断问题。
	# --------------------------------------------------------
	var total_cap: int = max_fish + max_algae
	var target_total_f: float = clampf(round(budget * 10.0), 0.0, float(total_cap))
	var target_total: int = int(target_total_f)

	# --------------------------------------------------------
	# 4) 按 bias 分配比例：target_total -> target_fish/target_algae
	# - sum_bias 防止除 0
	# - 用 clampf + round 保证可预测且不产生 Variant 推断警告
	# --------------------------------------------------------
	var sum_bias: float = maxf(0.001, fish_bias + algae_bias)

	var target_fish_f: float = clampf(
		round(float(target_total) * fish_bias / sum_bias),
		0.0,
		float(max_fish)
	)
	var target_algae_f: float = clampf(
		round(float(target_total) * algae_bias / sum_bias),
		0.0,
		float(max_algae)
	)

	var target_fish: int = int(target_fish_f)
	var target_algae: int = int(target_algae_f)

	# （可选）未来如果你要更“速率化”生成，可以在这里用 spawn_rate_scale 控制逐步增量
	# 目前版本为了简单与稳定：直接稳态逼近（立刻到目标）

	# --------------------------------------------------------
	# 5) 生成 / 回收：让当前数量逼近目标数量
	# --------------------------------------------------------
	_spawn_to_target(target_fish, target_algae)

	# --------------------------------------------------------
	# 6) 死亡：最小版对鱼做随机 despawn（每帧最多 1 条）
	# --------------------------------------------------------
	_apply_death(dt, death_fish)


# ------------------------------------------------------------
# 生成 / 回收：稳态逼近目标数量
# ------------------------------------------------------------
func _spawn_to_target(target_fish: int, target_algae: int) -> void:
	_cleanup_dead_refs()

	# --- 生成鱼 ---
	while _fish.size() < target_fish and _fish.size() < max_fish:
		var n: Node = _spawn_one(fish_scene)
		if n == null:
			break
		_fish.append(n)

	# --- 生成藻 ---
	while _algae.size() < target_algae and _algae.size() < max_algae:
		var n: Node = _spawn_one(algae_scene)
		if n == null:
			break
		_algae.append(n)

	# --- 回收多余（从尾部删，避免震荡）---
	while _fish.size() > target_fish and _fish.size() > 0:
		var n: Node = _fish.pop_back()
		if is_instance_valid(n):
			n.queue_free()

	while _algae.size() > target_algae and _algae.size() > 0:
		var n: Node = _algae.pop_back()
		if is_instance_valid(n):
			n.queue_free()


# ------------------------------------------------------------
# 死亡（最小版）：将 death_bias 映射为“每秒死亡概率”
# - 温和：避免瞬间死光
# - 稳定：每帧最多杀 1 条鱼，避免抖动
# ------------------------------------------------------------
func _apply_death(dt: float, death_bias: float) -> void:
	_cleanup_dead_refs()
	if _fish.is_empty():
		return

	# death_bias 大概 0~0.5+，映射到 0~0.2/s 左右（可调）
	# clampf 用于避免 Variant 推断警告
	var p_per_sec: float = clampf(death_bias * 0.4 * death_rate_scale, 0.0, 0.5)

	# 把“每秒概率”换算成“本帧概率”
	# p = 1 - (1 - p_per_sec)^dt
	var p: float = 1.0 - pow(1.0 - p_per_sec, dt)

	# 每帧最多杀 1 条，避免抖
	if randf() < p:
		var idx: int = int(randi() % _fish.size())
		var n: Node = _fish[idx]
		if is_instance_valid(n):
			n.queue_free()
		_fish.remove_at(idx)


# ------------------------------------------------------------
# 实例化一个实体，并放到父 Layer 下
# ------------------------------------------------------------
func _spawn_one(scene: PackedScene) -> Node:
	if scene == null:
		return null

	# 显式类型，避免 Variant 推断警告
	var inst: Node = scene.instantiate() as Node
	if inst == null:
		return null

	# 随机点（局部坐标）
	var x: float = randf_range(spawn_rect.position.x, spawn_rect.position.x + spawn_rect.size.x)
	var y: float = randf_range(spawn_rect.position.y, spawn_rect.position.y + spawn_rect.size.y)

	# 推荐实体是 Node2D（便于定位）
	if inst is Node2D:
		(inst as Node2D).position = Vector2(x, y)

	# 挂到父层：保持“每层自包含”，不污染全局
	var layer: Node = get_parent()
	if layer != null:
		layer.add_child(inst)

	return inst


# ------------------------------------------------------------
# 清理无效引用：避免数组里留着已 free 的对象
# ------------------------------------------------------------
func _cleanup_dead_refs() -> void:
	_fish = _fish.filter(func(n: Node) -> bool: return is_instance_valid(n))
	_algae = _algae.filter(func(n: Node) -> bool: return is_instance_valid(n))

# 只读输出：给 DebugOverlay/未来UI用
func get_population_state() -> Dictionary:
	return {
		"fish": _fish.size(),
		"algae": _algae.size(),
		"max_fish": max_fish,
		"max_algae": max_algae
	}
