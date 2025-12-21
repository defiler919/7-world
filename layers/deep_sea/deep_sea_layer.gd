# res://layers/deep_sea/deep_sea_layer.gd
extends "res://core/layer/layer_base.gd"

# 这个 index 必须与你 WorldRoot 的层顺序一致（你当前 layer=0/1）
# 你现在截图里 Layer:0，所以 deep_sea 如果不是 0，请改成正确值
@export var layer_index: int = 1

@export var tau_spawn: float = 4.0
@export var tau_death: float = 8.0
@export var tau_budget: float = 10.0
@export var tau_hazard: float = 12.0

# 缓存引用（只读）
var _ecology_rules: Node = null

func _ready() -> void:
	# ⚠️ 很重要：让 LayerBase._ready 跑到（用于 state.name 等）
	super._ready()
	_ecology_rules = _find_ecology_rules()

func get_layer_intent() -> Dictionary:
	if _ecology_rules == null:
		_ecology_rules = _find_ecology_rules()
		if _ecology_rules == null:
			return {}

	if not _ecology_rules.has_method("get_layer_intent"):
		return {}

	var intent: Dictionary = _ecology_rules.get_layer_intent(layer_index)
	return intent

func _tau_for_key(key: String) -> float:
	if key.begins_with("spawn."):
		return tau_spawn
	if key.begins_with("death."):
		return tau_death
	if key.begins_with("budget."):
		return tau_budget
	if key.begins_with("hazard."):
		return tau_hazard
	return tau_misc

# ------------------------------------------------------------
# 查找 EcologyRules：不写死路径，尽量从场景树里找
# ------------------------------------------------------------
func _find_ecology_rules() -> Node:
	# 1) 优先按类型/脚本名全局找（最稳）
	#    如果你 ecology_rules.gd 有 `class_name EcologyRules`，这里会更精准
	var nodes := get_tree().get_nodes_in_group("ecology_rules")
	if not nodes.is_empty():
		return nodes[0]

	# 2) 按节点名查找（常见：WorldRoot 下挂 EcologyRules）
	var root := get_tree().current_scene
	if root == null:
		return null

	# 深度查找：名字叫 "EcologyRules" 的节点
	var found := _find_node_by_name(root, "EcologyRules")
	if found != null:
		return found

	# 3) 兜底：遍历所有节点，找有 get_layer_intent 的那个
	for n in get_tree().get_nodes_in_group("all"):
		if n != null and n.has_method("get_layer_intent"):
			return n

	# 兜底失败
	return null

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for c in node.get_children():
		if c is Node:
			var r := _find_node_by_name(c, target_name)
			if r != null:
				return r
	return null
