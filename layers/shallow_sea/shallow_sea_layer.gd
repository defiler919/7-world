extends "res://core/layer/layer_base.gd"

# ⚠️ 这里通常是 0（浅海在最上层）
@export var layer_index: int = 0

@export var tau_spawn: float = 2.5     # 浅海变化更快（示例）
@export var tau_death: float = 6.0
@export var tau_budget: float = 8.0
@export var tau_hazard: float = 10.0

var _ecology_rules: Node = null

func _ready() -> void:
	super._ready()
	_ecology_rules = _find_ecology_rules()

func get_layer_intent() -> Dictionary:
	if _ecology_rules == null:
		_ecology_rules = _find_ecology_rules()
		if _ecology_rules == null:
			return {}

	if not _ecology_rules.has_method("get_layer_intent"):
		return {}

	return _ecology_rules.get_layer_intent(layer_index)

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
# 查找 EcologyRules（与 deep_sea_layer 保持一致）
# ------------------------------------------------------------
func _find_ecology_rules() -> Node:
	var nodes := get_tree().get_nodes_in_group("ecology_rules")
	if not nodes.is_empty():
		return nodes[0]

	var root := get_tree().current_scene
	if root == null:
		return null

	return _find_node_by_name(root, "EcologyRules")

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for c in node.get_children():
		if c is Node:
			var r := _find_node_by_name(c, target_name)
			if r != null:
				return r
	return null
