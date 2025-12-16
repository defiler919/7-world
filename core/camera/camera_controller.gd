# 模块：core/camera/camera_controller.gd
# 职责：单相机控制器：左右平移 + 上下切层，保证不瞬移、不卡边界。
# 输入：输入事件、WorldConfig、当前层索引/目标位置。
# 输出：Camera2D 的目标位置/平滑运动。
# 禁止：
# - 直接操作生态/实体
# - 为了“好看”改世界状态
extends Node

@export var camera_path: NodePath
@export var world_root_path: NodePath
@export var pan_speed: float = 900.0

# 切换冷却（秒）：滚轮/切层/切列 都走同一个门闸
@export var switch_cooldown_sec: float = 0.15

var camera: Camera2D
var world_root: Node
var config: WorldConfig


# 当前所在“场景格”
var layer_index: int = 0
var col_index: int = 0  # 0=左（海水），1=右（陆地）

# cell 内偏移（相对 cell_center）
var local_offset: Vector2 = Vector2.ZERO

# 切换冷却计时
var _switch_cd_left: float = 0.0

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

	# 初始对准：layer0,col0 的中心
	var start_center: Vector2 = config.get_cell_center(layer_index, col_index)
	camera.global_position = start_center
	local_offset = Vector2.ZERO

func _process(delta: float) -> void:
	if camera == null or config == null:
		return

	# 冷却计时
	if _switch_cd_left > 0.0:
		_switch_cd_left = max(0.0, _switch_cd_left - delta)

	# 1) 场景内移动（WASD 连续）
	var pan_vec := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	local_offset += pan_vec * pan_speed * delta

	# 2) 计算目标位置：cell_center + local_offset
	var target_pos: Vector2 = config.get_cell_center(layer_index, col_index) + local_offset

	# 3) clamp 到当前 cell 内（保证“到边缘停止”）
	var vp: Vector2 = get_viewport().get_visible_rect().size
	target_pos = config.clamp_camera_center_to_cell(target_pos, vp, layer_index, col_index)

	# 4) 反推 local_offset（被 clamp 后要同步回来，否则会“越界累积”）
	local_offset = target_pos - config.get_cell_center(layer_index, col_index)

	# 5) 平滑移动（不瞬移）
	camera.global_position = camera.global_position.lerp(target_pos, 1.0 - pow(0.0001, delta))

func _unhandled_input(event: InputEvent) -> void:
	if config == null:
		return

	# --- 键盘：切层/切列（离散） ---
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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_try_switch_layer(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_try_switch_layer(+1)

func _try_switch_layer(dir: int) -> void:
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec

	var max_layer : = config.layer_count() - 1
	layer_index = clamp(layer_index + dir, 0, max_layer)
	# 不清空 local_offset：保留你在当前场景内的浏览偏移
	# clamp 会在 _process 自动处理

func _try_toggle_col() -> void:
	if _switch_cd_left > 0.0:
		return
	_switch_cd_left = switch_cooldown_sec

	# 只有2列：0 <-> 1
	col_index = 1 - col_index
