# ============================================================
# 模块宪法：core/world/world_config.gd
# ============================================================
# 1) 这个模块只负责“世界坐标规则/几何划分”：
#    - 每一层（layer）在世界里怎么排布（竖直叠放）
#    - 每一层里有几列（cols），每列代表一个“场景格/区域”(cell)
#    - 每个 cell 的宽高是多少（cell_width/cell_height）
#    - 提供常用的几何工具：origin / rect / center / clamp
#
# 2) 这个模块不负责：
#    - 摄像机移动逻辑（那是 CameraController 的事）
#    - 加载/实例化层场景（那是 WorldRoot 的事）
#    - 生态/实体/规则（都不属于这里）
#
# 3) 坐标约定（非常重要）：
#    - X 轴：左右方向（列 col_index），0 在最左边
#    - Y 轴：上下方向（层 layer_index），0 在最上层
#    - 每一层的“高度”固定等于 cell_height
#    - 每一列的“宽度”固定等于 cell_width
#
# 4) 你现在的世界结构（演示阶段）：
#    - cols = 2 → 左右两列 → 例如 0=海水，1=陆地（你后面可自行定义含义）
#    - layer_scene_paths 里有 N 个路径 → N 层（layer_index: 0..N-1）
#    - 总“场景格”数量 = layer_count() * cols
#      例如：7 层 * 2 列 = 14 个 cell（你前面描述的 7*2=14）
#
# 5) 设计风格（新手重点）：
#    - WorldConfig 是“纯数学/纯规则”，不依赖场景树
#    - 它应该永远可单独 new() 并安全使用
# ============================================================

extends Resource
class_name WorldConfig

# ----------------------------
# 世界切分参数：cell 的大小
# ----------------------------

# 单个场景格（cell）尺寸
# 解释：每个 cell 是一个固定大小的矩形区域，用来承载“一个场景/一个房间/一个区域”的内容
# 你现在：宽 5000，高 3000
#
# 注意（新手坑）：
# - cell 必须“足够大”，至少要大于窗口/viewport，否则 clamp 会变得不合理
# - 如果 viewport 比 cell 还大，你就不可能“看不见 cell 外面”
@export var cell_width: int = 5000
@export var cell_height: int = 3000

# 列数：左右两个场景（海水/陆地）
# 解释：一层里有几列 cell。
# cols=2 就是：这一层被左右切成两个并排的“场景格”。
#
# 约定：
# - col_index 的合法范围是 [0, cols-1]
@export var cols: int = 2

# ----------------------------
# 层的定义：每层一个场景文件
# ----------------------------

# 演示阶段只做两层（顺序即 layer_index：0=浅海，1=深海）
# 解释：这个数组的“顺序”就是 layer_index 的含义：
#   layer_scene_paths[0] → layer_index = 0
#   layer_scene_paths[1] → layer_index = 1
#
# 约定：
# - layer_index 的合法范围是 [0, layer_count()-1]
@export var layer_scene_paths: Array[String] = [
	"res://layers/shallow_sea/shallow_sea_layer.tscn",
	"res://layers/deep_sea/deep_sea_layer.tscn"
]

# 返回当前有多少层
func layer_count() -> int:
	return layer_scene_paths.size()

# 返回“每一层整体的宽度”
# 解释：一层有 cols 列，每列宽 cell_width，所以这一层总宽 = cell_width * cols
func layer_width() -> int:
	return cell_width * cols

# ----------------------------
# 层（layer）相关几何
# ----------------------------

# 获取某一层在世界坐标中的“左上角原点”
# 解释：
#   - 所有层都从 x=0 开始
#   - 第 layer_index 层的 y = layer_index * cell_height
# 因为每一层高度固定为 cell_height，所以层与层是“竖直叠放”的。
func get_layer_origin(layer_index: int) -> Vector2:
	return Vector2(0, layer_index * cell_height)

# 获取某一层的矩形范围（Rect2）
# 解释：Rect2(左上角位置, 尺寸)
#   - 位置：get_layer_origin(layer_index)
#   - 尺寸：宽=layer_width(), 高=cell_height
func get_layer_rect(layer_index: int) -> Rect2:
	return Rect2(get_layer_origin(layer_index), Vector2(layer_width(), cell_height))

# ----------------------------
# 场景格（cell）相关几何
# ----------------------------

# 获取某一层、某一列的 cell 的“左上角原点”
# 解释：
#   - X 方向：col_index * cell_width
#   - Y 方向：layer_index * cell_height
# 所以同一层里，col_index=0 在左边，col_index=1 在右边（如果 cols=2）。
#
# 注意：
# - 这里不做 col_index/layer_index 的越界检查（保持“纯规则/纯计算”）
# - 越界保护应由调用方（CameraController / WorldRoot）负责
func get_cell_origin(layer_index: int, col_index: int) -> Vector2:
	return Vector2(col_index * cell_width, layer_index * cell_height)

# 获取某个 cell 的矩形范围
# 解释：
#   - 位置：get_cell_origin(layer_index, col_index)
#   - 尺寸：宽=cell_width，高=cell_height
func get_cell_rect(layer_index: int, col_index: int) -> Rect2:
	return Rect2(get_cell_origin(layer_index, col_index), Vector2(cell_width, cell_height))

# 获取某个 cell 的中心点
# 解释：中心 = 左上角 + 尺寸的一半
func get_cell_center(layer_index: int, col_index: int) -> Vector2:
	var r: Rect2 = get_cell_rect(layer_index, col_index)
	return r.position + r.size * 0.5

# ----------------------------
# 摄像机夹取（clamp）工具
# ----------------------------

# 把“摄像机中心点”限制在某个 cell 内，避免看到 cell 外面
#
# 参数解释：
# - pos：你想让相机中心去的位置（世界坐标）
# - viewport_size：当前屏幕/窗口可视区域大小（像素），例如 1152x648
# - layer_index / col_index：当前所在的 cell
#
# 核心思路（新手重点看这个）：
# - 相机是“中心点”对准 pos
# - 但屏幕有宽高 → 相机中心不能贴到 cell 边缘，否则屏幕会露出 cell 外
# - 所以我们要留出半个屏幕的“安全边距”：
#     half = viewport_size * 0.5
# - 允许的中心点范围：
#     min_x = cell_left + half.x
#     max_x = cell_right - half.x
#     min_y = cell_top  + half.y
#     max_y = cell_bottom - half.y
# - 最后 clamp(pos.x, min_x, max_x) 进行夹取
#
# 注意（新手坑）：
# - 如果 viewport_size 比 cell 大：
#   例如 half.x > cell_width/2
#   那么 min_x 可能会大于 max_x，夹取就会“很怪”
#   这时正确做法通常是：增大 cell，或者允许看到边界外，或者做缩放策略
func clamp_camera_center_to_cell(
	pos: Vector2,
	viewport_size: Vector2,
	layer_index: int,
	col_index: int
) -> Vector2:
	var rect: Rect2 = get_cell_rect(layer_index, col_index)
	var half: Vector2 = viewport_size * 0.5

	var min_x: float = rect.position.x + half.x
	var max_x: float = rect.position.x + rect.size.x - half.x
	var min_y: float = rect.position.y + half.y
	var max_y: float = rect.position.y + rect.size.y - half.y

	return Vector2(
		clamp(pos.x, min_x, max_x),
		clamp(pos.y, min_y, max_y)
	)
