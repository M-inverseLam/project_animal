extends Camera3D

@export var target_path: NodePath = NodePath("../chicken01")
@export var follow_offset := Vector3(0.0, 26.121084, 25.622486)
@export var spring_strength: float = 35.0
@export var spring_damping: float = 10.0
@export var shake_strength: float = 0.45

var _target: Node3D
var _velocity := Vector3.ZERO
var _shake_time_left := 0.0
var _shake_duration := 0.0
var _shake_strength := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_target = get_node_or_null(target_path) as Node3D
	current = true

	if _target != null:
		global_position = _target.global_position + follow_offset


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var desired_position := _target.global_position + follow_offset
	var displacement := desired_position - global_position
	var acceleration := displacement * spring_strength - _velocity * spring_damping

	_velocity += acceleration * delta
	global_position += _velocity * delta

	if _shake_time_left > 0.0:
		_apply_shake(delta)


func shake(duration: float = 0.5, strength: float = -1.0) -> void:
	_shake_duration = maxf(duration, 0.0)
	_shake_time_left = _shake_duration
	_shake_strength = self.shake_strength if strength < 0.0 else strength


func _apply_shake(delta: float) -> void:
	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	if _shake_duration <= 0.0:
		return

	var fade := _shake_time_left / _shake_duration
	var offset := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		0.0
	) * _shake_strength * fade

	global_position += global_transform.basis * offset
