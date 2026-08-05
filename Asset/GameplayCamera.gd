extends Camera3D

@export var target_path: NodePath = NodePath("../chicken01")
## X offsets the camera sideways, Y adjusts framing, and Z controls follow distance.
## A Y value of 0 keeps the target centered for the selected camera angle.
@export var follow_offset := Vector3(0.0, 0.0, 25.622486)
@export_range(-89.0, 0.0, 0.5, "degrees") var camera_angle: float = -45.0
@export var spring_strength: float = 35.0
@export var spring_damping: float = 10.0

@export_group("Camera Shake")
@export var camera_shake_duration: float = 0.8
@export var camera_shake_strength: float = 0.3

var _target: Node3D
var _velocity := Vector3.ZERO
var _follow_position := Vector3.ZERO
var _shake_time_left := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_target = get_node_or_null(target_path) as Node3D
	current = true
	rotation_degrees.x = camera_angle

	if _target != null:
		_follow_position = _target.global_position + _get_centered_follow_offset()
		global_position = _follow_position
	else:
		_follow_position = global_position


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var desired_position := _target.global_position + _get_centered_follow_offset()
	var displacement := desired_position - _follow_position
	var acceleration := displacement * spring_strength - _velocity * spring_damping

	_velocity += acceleration * delta
	_follow_position += _velocity * delta

	var shake_offset := Vector3.ZERO
	if _shake_time_left > 0.0:
		shake_offset = _calculate_shake_offset(delta)

	global_position = _follow_position + global_transform.basis * shake_offset


func _get_centered_follow_offset() -> Vector3:
	var centered_height := tan(deg_to_rad(-camera_angle)) * follow_offset.z
	return Vector3(follow_offset.x, centered_height + follow_offset.y, follow_offset.z)


func shake(duration: float, strength: float) -> void:
	var requested_duration := maxf(duration, 0.0)
	var requested_strength := maxf(strength, 0.0)
	if requested_duration <= 0.0:
		return

	if _shake_time_left > requested_duration:
		_shake_strength = maxf(_shake_strength, requested_strength)
		return

	_shake_duration = requested_duration
	_shake_time_left = requested_duration
	_shake_strength = requested_strength


func shake_camera() -> void:
	shake(camera_shake_duration, camera_shake_strength)


func _calculate_shake_offset(delta: float) -> Vector3:
	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	if _shake_duration <= 0.0:
		return Vector3.ZERO

	var fade := _shake_time_left / _shake_duration
	return Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		0.0
	) * _shake_strength * fade
