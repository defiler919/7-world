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
# （以下原注释全部保留）
# ============================================================


#推荐配置参数：
#pan_accel_strength = 90000.0
#pan_damping = 16.0
#pan_max_speed = 5200.0
#pan_release_damping = 52.0
#pan_stop_speed = 28.0


extends Node

# ------------------------------------------------------------
# Inspector 可配置项（不硬编码）
# ------------------------------------------------------------

@export var camera_path: NodePath
@export var world_root_path: NodePath

# 平移速度（像素/秒）
@export var pan_speed: float = 900.0

# ⭐ 新增：惯性参数（Day4）
@export var pan_accel_strength: float = 80000.0   # 推力强度
@export var pan_damping: float = 14.0             # 阻尼（越大越“粘”）

@export var switch_cooldown_sec: float = 0.15

# ⭐ 新增：速度上限与“松手刹车”
@export var pan_max_speed: float = 3500.0        # 相机平移最大速度（像素/秒）
@export var pan_release_damping: float = 28.0    # 松手后的强阻尼（越大停得越快）
@export var pan_stop_speed: float = 12.0         # 低于这个速度直接归零，避免尾巴

# ------------------------------------------------------------
# 运行时引用
# ------------------------------------------------------------
var camera: Camera2D
var world_root: Node
var config: WorldConfig

# ------------------------------------------------------------
# 当前所在“场景格”的索引
# ------------------------------------------------------------
var layer_index: int = 0
var col_index: int = 0

# ------------------------------------------------------------
# 场景格（cell）内偏移
# ------------------------------------------------------------
var local_offset: Vector2 = Vector2.ZERO

# ⭐ 新增：惯性状态（Day4）
var pan_velocity: Vector2 = Vector2.ZERO
var pan_accel: Vector2 = Vector2.ZERO

# ------------------------------------------------------------
# 切换冷却计时
# ------------------------------------------------------------
var _switch_cd_left: float = 0.0

# ------------------------------------------------------------
# 生命周期：节点准备完成
# ------------------------------------------------------------
func _ready() -> void:
	camera = get_node_or_null(camera_path) as Camera2D
	world_root = get_node_or_null(world_root_path)
	config = world_root.config as WorldConfig

	if camera == null:
		push_error("CameraController: camera_path not set or not found.")
		return
	if world_root == null:
		push_error("CameraController: world_root_path not set or not found.")
		return
	if "config" in world_root:
		config = world_root.config
	if config == null:
		push_error("CameraController: WorldConfig missing.")
		return

	var start_center: Vector2 = config.get_cell_center(layer_index, col_index)
	camera.global_position = start_center
	local_offset = Vector2.ZERO
	pan_velocity = Vector2.ZERO

# ------------------------------------------------------------
# 每帧更新：计算目标位置并平滑移动相机
# ------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or config == null:
		return

	# 0) 更新冷却计时
	if _switch_cd_left > 0.0:
		_switch_cd_left = max(0.0, _switch_cd_left - delta)

	# --------------------------------------------------------
	# 1) 输入 → 加速度（而不是直接改 offset）
	# --------------------------------------------------------
	var input_vec := Input.get_vector(
		"pan_left",
		"pan_right",
		"pan_up",
		"pan_down"
	)

	pan_accel = input_vec * pan_accel_strength

	# 2) 速度积分（惯性）
	pan_velocity += pan_accel * delta

	# ✅ 速度上限：不管你 accel 多大，最终速度不会无限飙
	pan_velocity = pan_velocity.limit_length(pan_max_speed)

	# ✅ 分离阻尼：按住时“轻阻尼”、松手时“重刹车”
	var has_input := input_vec.length_squared() > 0.0001
	var damping := pan_damping if has_input else pan_release_damping

	# ✅ 用指数衰减做阻尼：稳定、可控、帧率无关
	#   pan_velocity *= exp(-damping * delta)
	pan_velocity *= exp(-damping * delta)

	# ✅ 尾巴阈值：很小速度直接停
	if pan_velocity.length() < pan_stop_speed:
		pan_velocity = Vector2.ZERO

	# --------------------------------------------------------
	# 3) 位移积分
	# --------------------------------------------------------
	local_offset += pan_velocity * delta

	# --------------------------------------------------------
	# 4) 计算目标相机位置
	# --------------------------------------------------------
	var target_pos := config.get_cell_center(layer_index, col_index) + local_offset

	# --------------------------------------------------------
	# 5) Clamp 到 cell 内
	# --------------------------------------------------------
	var vp := get_viewport().get_visible_rect().size
	target_pos = config.clamp_camera_center_to_cell(
		target_pos,
		vp,
		layer_index,
		col_index
	)

	# --------------------------------------------------------
	# 6) 反推 local_offset + 边界速度衰减
	# --------------------------------------------------------
	var new_offset := target_pos - config.get_cell_center(layer_index, col_index)

	# 如果被 clamp，说明撞墙 → 吃掉法向速度
	var delta_offset := new_offset - local_offset
	if delta_offset.length() < 0.001:
		pan_velocity *= 0.2

	local_offset = new_offset

	# --------------------------------------------------------
	# 7) 相机平滑跟随
	# --------------------------------------------------------
	camera.global_position = camera.global_position.lerp(
		target_pos,
		1.0 - pow(0.0001, delta)
	)

# ------------------------------------------------------------
# 输入：离散切换（键盘/鼠标滚轮）
# ------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if config == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if Input.is_action_just_pressed("layer_up"):
			_try_switch_layer(-1)
		elif Input.is_action_just_pressed("layer_down"):
			_try_switch_layer(+1)

		if Input.is_action_just_pressed("col_toggle"):
			_try_toggle_col()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_try_switch_layer(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_try_switch_layer(+1)

# ------------------------------------------------------------
# 内部：尝试切换层
# ------------------------------------------------------------
func _try_switch_layer(dir: int) -> void:
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec

	var max_layer := config.layer_count() - 1
	layer_index = clamp(layer_index + dir, 0, max_layer)

# ------------------------------------------------------------
# 内部：左右切换列
# ------------------------------------------------------------
func _try_toggle_col() -> void:
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec
	col_index = 1 - col_index

# ------------------------------------------------------------
# 只读快照
# ------------------------------------------------------------
func get_camera_state_snapshot() -> Dictionary:
	return {
		"layer_index": layer_index,
		"col_index": col_index,
		"local_offset": local_offset,
		"velocity": pan_velocity,
		"cooldown_left": _switch_cd_left
	}
