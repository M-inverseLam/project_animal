extends Node3D

@export var enabled: bool = true
@export var movement_axis := Vector3.RIGHT
@export var movement_distance: float = 0.2
@export var movement_speed: float = 0.8

var _base_position := Vector3.ZERO
var _travel := 0.0
var _direction := 1.0


func _ready() -> void:
	_base_position = position


func _physics_process(delta: float) -> void:
	if not enabled:
		position = _base_position
		return

	var axis := movement_axis.normalized() if movement_axis.length_squared() > 0.0001 else Vector3.RIGHT
	var max_distance := maxf(movement_distance, 0.0)
	if max_distance <= 0.0:
		position = _base_position
		return

	_travel += movement_speed * delta * _direction
	if _travel > max_distance:
		_travel = max_distance
		_direction = -1.0
	elif _travel < -max_distance:
		_travel = -max_distance
		_direction = 1.0

	position = _base_position + axis * _travel
