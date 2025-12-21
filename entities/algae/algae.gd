extends Node2D

@export var sway_amplitude := 3.0
@export var sway_speed := 0.8

var _t := randf() * TAU
var _base_pos := Vector2.ZERO

func _ready():
	_base_pos = position

func _process(dt):
	_t += dt * sway_speed
	position.x = _base_pos.x + sin(_t) * sway_amplitude
