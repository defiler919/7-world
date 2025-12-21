extends Node2D
class_name Fish

@export var speed: float = 20.0
var _dir := Vector2.RIGHT.rotated(randf() * TAU)

func _process(dt: float) -> void:
	# 极简漂移，后面再做 flocking/AI
	position += _dir * speed * dt

	# 小范围抖动
	if randf() < 0.02:
		_dir = _dir.rotated(randf_range(-0.4, 0.4)).normalized()
