# ============================================================
# 模块宪法：core/camera/camera_controller.gd
# ============================================================
#
# 【这个模块是什么？】
# CameraController 是“单相机控制器”：
# - 它不画画面、不管生态、不管实体
# - 它只负责：把玩家输入 → 转换成 Camera2D 的平滑移动
#
# 你可以把它理解成“镜头操作系统”。
#
# ------------------------------------------------------------
# 【它负责什么？】
# 1) 场景内移动（Pan）
#    - WASD 是连续移动：在当前场景格（cell）里移动视野
#
# 2) 场景切换（Switch Cell）
#    - 鼠标滚轮：上下切层（layer）
#    - Q/E：上下切层（备用）
#    - Tab：左右切列（col，只有两列，所以用 toggle）
#
# 3) 防抖/冷却（Cooldown）
#    - 因为滚轮/触控板可能一次触发很多次事件
#    - 所以所有“切换”都走一个冷却门闸，避免连跳
#
# 4) 相机边界限制（Clamp）
#    - 相机中心不能跑出当前 cell 的边界
#    - 否则屏幕会看到 cell 外（露出灰底/空白）
#
# ------------------------------------------------------------
# 【它不负责什么？（非常重要）】
# ❌ 不加载层场景（WorldRoot 负责）
# ❌ 不决定世界几层、每层多宽（WorldConfig 负责）
# ❌ 不写生态/入侵/稀有事件（ecology/presentation 负责）
# ❌ 不为了“好看”直接修改世界状态
#
# ------------------------------------------------------------
# 【核心数据模型（新手必看）】
# 世界被切成很多“场景格”（cell）：
# - layer_index：第几层（上下）
# - col_index：第几列（左右，0=左/海水，1=右/陆地）
#
# 一个 cell 有固定宽高（由 WorldConfig 提供）：
# - cell_width
# - cell_height
#
# 相机最终的目标位置 = cell_center + local_offset
# - cell_center：当前格子的中心点
# - local_offset：你在格子内“偏离中心”的量（WASD 改这个）
#
# 然后把目标位置 clamp 到 cell 内，最后 lerp 平滑过去。
# ============================================================

extends Node

# ------------------------------------------------------------
# Inspector 可配置项（不硬编码）
# ------------------------------------------------------------

# 相机节点路径（在场景树里选：../WorldCamera）
@export var camera_path: NodePath

# 世界根节点路径（在场景树里选：../WorldRoot）
@export var world_root_path: NodePath

# 平移速度（像素/秒）：WASD 场景内移动手感
@export var pan_speed: float = 900.0

# 切换冷却（秒）：
# - 滚轮、Q/E、Tab 都会走这个门闸
# - 防止“滚一下跳好几层”
@export var switch_cooldown_sec: float = 0.15

# ------------------------------------------------------------
# 运行时引用（ready 后初始化）
# ------------------------------------------------------------
var camera: Camera2D
var world_root: Node
var config: WorldConfig

# ------------------------------------------------------------
# 当前所在“场景格”的索引
# ------------------------------------------------------------

# 当前层（上下）
var layer_index: int = 0

# 当前列（左右）
# 约定：0=左（海水），1=右（陆地）
var col_index: int = 0

# ------------------------------------------------------------
# 场景格（cell）内偏移
# ------------------------------------------------------------
# local_offset 表示“相机中心相对 cell 中心的偏移量”
# - WASD 会不断修改它
# - 切换 layer/col 时，不清空它 → 保留你当前浏览的位置
var local_offset: Vector2 = Vector2.ZERO

# ------------------------------------------------------------
# 切换冷却计时
# ------------------------------------------------------------
# > 0 代表还在冷却中，新的切换请求会被忽略
var _switch_cd_left: float = 0.0

# ------------------------------------------------------------
# 生命周期：节点准备完成
# ------------------------------------------------------------
func _ready() -> void:
	# 1) 找到相机节点
	camera = get_node_or_null(camera_path) as Camera2D

	# 2) 找到世界根节点
	world_root = get_node_or_null(world_root_path)

	# 3) 从 WorldRoot 里取 WorldConfig
	# 注意：世界配置属于 WorldRoot 持有，CameraController 只“读取”
	# 你现在写了两次赋值（先 as 强转一次，后面又 if "config" 再赋一次），
	# 这不影响运行，只是重复。我们不改代码，只在这里说明。
	config = world_root.config as WorldConfig

	# --- 基础安全检查：缺任何一个都无法工作 ---
	if camera == null:
		push_error("CameraController: camera_path not set or not found.")
		return
	if world_root == null:
		push_error("CameraController: world_root_path not set or not found.")
		return

	# 如果 world_root 真的有 config 字段，则再取一次
	if "config" in world_root:
		config = world_root.config
	if config == null:
		push_error("CameraController: WorldConfig missing.")
		return

	# 初始对准：layer0,col0 的中心
	# （这一步决定：一开始进入游戏，相机就正对“世界中心”而不是歪着）
	var start_center: Vector2 = config.get_cell_center(layer_index, col_index)
	camera.global_position = start_center
	local_offset = Vector2.ZERO

# ------------------------------------------------------------
# 每帧更新：计算目标位置并平滑移动相机
# ------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or config == null:
		return

	# 0) 更新冷却计时
	if _switch_cd_left > 0.0:
		_switch_cd_left = max(0.0, _switch_cd_left - delta)

	# 1) 场景内移动（WASD 连续）
	# 这里用 InputMap 的 action 名称，而不是写死按键
	# 好处：以后玩家可以自定义按键，不用改代码
	var pan_vec := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	local_offset += pan_vec * pan_speed * delta

	# 2) 把“cell + 偏移”合成目标世界坐标
	# target_pos 就是我们希望相机中心去到的位置
	var target_pos: Vector2 = config.get_cell_center(layer_index, col_index) + local_offset

	# 3) clamp 到当前 cell 内（保证“到边缘停止”）
	# 关键点：相机中心要留出“半个屏幕”作为边距，否则会看到 cell 外
	var vp: Vector2 = get_viewport().get_visible_rect().size
	target_pos = config.clamp_camera_center_to_cell(target_pos, vp, layer_index, col_index)

	# 4) 反推 local_offset（重要！）
	# 为什么要做这一步？
	# - 如果你一直按住 WASD 往边界推，local_offset 会越加越大
	# - 但 clamp 会把 target_pos 卡住
	# - 如果不把 local_offset 同步回来，会产生“隐形积累”，松手时可能出现奇怪的跳动
	local_offset = target_pos - config.get_cell_center(layer_index, col_index)

	# 5) 平滑移动（不瞬移）
	# lerp + 指数衰减写法：能保证不同帧率下手感稳定
	camera.global_position = camera.global_position.lerp(target_pos, 1.0 - pow(0.0001, delta))

# ------------------------------------------------------------
# 输入：离散切换（键盘/鼠标滚轮）
# ------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if config == null:
		return

	# --- 键盘：切层/切列（离散） ---
	# 这里用 “just_pressed” 保证一次按下只触发一次
	if event is InputEventKey and event.pressed and not event.echo:
		# Q/E：上下切层（InputMap）
		if Input.is_action_just_pressed("layer_up"):
			_try_switch_layer(-1)
		elif Input.is_action_just_pressed("layer_down"):
			_try_switch_layer(+1)

		# Tab：左右切换（2列 toggle）
		if Input.is_action_just_pressed("col_toggle"):
			_try_toggle_col()

	# --- 鼠标滚轮：上下切层（离散 + 冷却） ---
	# 注意：触控板可能触发多次滚轮事件，所以必须配合冷却
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_try_switch_layer(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_try_switch_layer(+1)

# ------------------------------------------------------------
# 内部：尝试切换层（带冷却门闸）
# ------------------------------------------------------------
func _try_switch_layer(dir: int) -> void:
	# 冷却中就直接拒绝（防抖）
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec

	# 最大层索引 = 总层数 - 1
	var max_layer := config.layer_count() - 1

	# clamp 确保不会切出范围
	layer_index = clamp(layer_index + dir, 0, max_layer)

	# 不清空 local_offset：保留你在当前场景内的浏览偏移
	# clamp 会在 _process 自动处理

# ------------------------------------------------------------
# 内部：尝试左右切换列（两列 toggle）
# ------------------------------------------------------------
func _try_toggle_col() -> void:
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec

	# 只有2列：0 <-> 1
	col_index = 1 - col_index
	
	
# 只读快照：给 WorldRoot/Debug 用，不做任何控制行为
func get_camera_state_snapshot() -> Dictionary:
	return {
		"layer_index": layer_index,
		"col_index": col_index,
		"local_offset": local_offset,
		"cooldown_left": _switch_cd_left
	}


# ============================================================
# InputMap 动作清单（CameraController 依赖）
# ============================================================
#
# 说明：
# 本脚本【不会】直接读取具体按键（如 A / D / W / S），
# 而是只通过 InputMap 的“动作名”读取输入。
#
# 好处：
# - 玩家可自定义按键
# - 不同键盘布局（无方向键 / 笔记本）可适配
# - 手柄 / 触控 / AI 输入都能复用同一套逻辑
#
# ------------------------------------------------------------
# 一、场景内移动（连续输入）
# ------------------------------------------------------------
# 用于在“当前场景格（cell）”内平移相机
#
# pan_left   ：向左平移（默认绑定 A）
# pan_right  ：向右平移（默认绑定 D）
# pan_up     ：向上平移（默认绑定 W）
# pan_down   ：向下平移（默认绑定 S）
#
# CameraController 中使用方式：
#   Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
#
# ------------------------------------------------------------
# 二、上下切层（离散输入 + 冷却）
# ------------------------------------------------------------
# 用于在不同“层（layer）”之间切换
# 每次触发只切换一层，受 switch_cooldown_sec 限制
#
# layer_up    ：切换到上一层
# layer_down  ：切换到下一层
#
# 默认建议绑定：
#   layer_up   → Q
#   layer_down → E
#
# 同时支持鼠标滚轮：
#   滚轮上 → layer_up
#   滚轮下 → layer_down
#
# ------------------------------------------------------------
# 三、左右切换场景列（离散输入 + 冷却）
# ------------------------------------------------------------
# 用于在同一层内，左右两个“场景格（col）”之间切换
#
# col_toggle ：左右列切换（仅 2 列时使用 toggle）
#
# 默认建议绑定：
#   col_toggle → Tab
#
# ------------------------------------------------------------
# 四、重要约定（给未来修改的人）
# ------------------------------------------------------------
# 1) CameraController 不应该新增“直接按键判断”
#    （如 Input.is_key_pressed(KEY_XXX)）
#    所有输入都应通过 InputMap 动作名进入。
#
# 2) 如果将来支持 >2 列：
#    - col_toggle 需要改为 col_left / col_right
#    - 但本脚本的整体结构依然适用
#
# 3) 如果将来支持手柄 / 触控：
#    - 只需要在 InputMap 中新增绑定
#    - CameraController 代码无需修改
#
# ============================================================
