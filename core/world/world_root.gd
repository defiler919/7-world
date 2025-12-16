extends Node
# 模块：core/world/world_root.gd
# 职责：世界入口，负责装配层级、驱动更新、对外提供世界级接口。
# 输入：WorldConfig、Registries、时间tick。
# 输出：当前层、世界状态聚合（WorldState）。
# 禁止：
# - 写具体生态规则/稀有现象
# - 硬引用 res://layers/* 具体脚本（必须走注册/接口）
@export var config: WorldConfig

var current_layer_index: int = 0
var layers: Array[Node2D] = []

func _ready() -> void:
	if config == null:
		config = WorldConfig.new()

	_load_layers()

func _load_layers() -> void:
	for l in layers:
		if is_instance_valid(l):
			l.queue_free()
	layers.clear()

	for i in range(config.layer_scene_paths.size()):
		var path: String = config.layer_scene_paths[i]
		var scene: PackedScene = load(path)
		if scene == null:
			push_error("Layer scene not found: %s" % path)
			continue

		var inst: Node = scene.instantiate()
		if inst is Node2D:
			var layer: Node2D = inst
			layer.position = config.get_layer_origin(i)
			add_child(layer)
			layers.append(layer)
		else:
			push_error("Layer root must be Node2D: %s" % path)
			inst.queue_free()
