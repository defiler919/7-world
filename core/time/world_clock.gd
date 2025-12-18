# ============================================================
# 模块宪法：core/time/world_clock.gd
# ============================================================
# 【是什么】
# WorldClock 是“世界时间与节奏源”。
# 它负责让世界时间持续推进，并按固定频率发出 tick 信号。
#
# 【负责什么】
# - world_time 累加（秒）
# - 可暂停（paused）
# - 可倍速（time_scale）
# - 发固定频率 tick（1s / 10s / 60s）
#
# 【不负责什么】
# - 不写生态、不生成实体、不改相机
# - 不关心当前层/当前列
#
# 【设计原则】
# - 任何系统想“每秒做一次事”，都订阅 tick_1s
# - 任何系统想“每分钟做一次事”，都订阅 tick_60s
# ============================================================

extends Node
class_name WorldClock

signal tick_1s(world_time: float, tick_index: int)
signal tick_10s(world_time: float, tick_index: int)
signal tick_60s(world_time: float, tick_index: int)

@export var paused: bool = false
@export var time_scale: float = 1.0

var world_time: float = 0.0

var _acc_1s: float = 0.0
var _acc_10s: float = 0.0
var _acc_60s: float = 0.0

var _i_1s: int = 0
var _i_10s: int = 0
var _i_60s: int = 0

func _process(delta: float) -> void:
	if paused:
		return

	# 允许倍速：0.5 慢速 / 2.0 快速
	var dt := delta * time_scale
	world_time += dt

	_acc_1s += dt
	_acc_10s += dt
	_acc_60s += dt

	# 用 while 是为了防止低帧率时漏 tick
	while _acc_1s >= 1.0:
		_acc_1s -= 1.0
		_i_1s += 1
		emit_signal("tick_1s", world_time, _i_1s)

	while _acc_10s >= 10.0:
		_acc_10s -= 10.0
		_i_10s += 1
		emit_signal("tick_10s", world_time, _i_10s)

	while _acc_60s >= 60.0:
		_acc_60s -= 60.0
		_i_60s += 1
		emit_signal("tick_60s", world_time, _i_60s)

func _ready() -> void:
	tick_1s.connect(func(t, i):
		print("tick_1s:", i, " time:", "%.2f" % t)
	)
