extends Node3D

@export var enabled: bool = true
@export var rotation_axis := Vector3.UP
@export var rotation_speed_degrees: float = 90.0
@export var use_ping_pong: bool = false
@export var ping_pong_angle_degrees: float = 45.0

var _base_basis := Basis.IDENTITY
var _current_angle_degrees := 0.0
var _ping_pong_direction := 1.0


func _ready() -> void:
	_base_basis = basis


func _physics_process(delta: float) -> void:
	if not enabled:
		return

	var axis := rotation_axis.normalized() if rotation_axis.length_squared() > 0.0001 else Vector3.UP
	var step := rotation_speed_degrees * delta
	if use_ping_pong:
		_update_ping_pong_rotation(axis, step)
		return

	rotate_object_local(axis, deg_to_rad(step))


func _update_ping_pong_rotation(axis: Vector3, step: float) -> void:
	var max_angle := maxf(ping_pong_angle_degrees, 0.0)
	if max_angle <= 0.0:
		basis = _base_basis
		_current_angle_degrees = 0.0
		return

	_current_angle_degrees += step * _ping_pong_direction
	if _current_angle_degrees > max_angle:
		_current_angle_degrees = max_angle
		_ping_pong_direction = -1.0
	elif _current_angle_degrees < -max_angle:
		_current_angle_degrees = -max_angle
		_ping_pong_direction = 1.0

	basis = _base_basis.rotated(axis, deg_to_rad(_current_angle_degrees))
