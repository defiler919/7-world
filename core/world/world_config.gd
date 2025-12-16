extends Resource
class_name WorldConfig

# 单个场景格（cell）尺寸
@export var cell_width: int = 5000
@export var cell_height: int = 3000

# 列数：左右两个场景（海水/陆地）
@export var cols: int = 2

# 演示阶段只做两层（顺序即 layer_index：0=浅海，1=深海）
@export var layer_scene_paths: Array[String] = [
	"res://layers/shallow_sea/shallow_sea_layer.tscn",
	"res://layers/deep_sea/deep_sea_layer.tscn"
]

func layer_count() -> int:
	return layer_scene_paths.size()

func layer_width() -> int:
	return cell_width * cols

func get_layer_origin(layer_index: int) -> Vector2:
	return Vector2(0, layer_index * cell_height)

func get_layer_rect(layer_index: int) -> Rect2:
	return Rect2(get_layer_origin(layer_index), Vector2(layer_width(), cell_height))

func get_cell_origin(layer_index: int, col_index: int) -> Vector2:
	return Vector2(col_index * cell_width, layer_index * cell_height)

func get_cell_rect(layer_index: int, col_index: int) -> Rect2:
	return Rect2(get_cell_origin(layer_index, col_index), Vector2(cell_width, cell_height))

func get_cell_center(layer_index: int, col_index: int) -> Vector2:
	var r: Rect2 = get_cell_rect(layer_index, col_index)
	return r.position + r.size * 0.5

func clamp_camera_center_to_cell(pos: Vector2, viewport_size: Vector2, layer_index: int, col_index: int) -> Vector2:
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
