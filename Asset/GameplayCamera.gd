extends Camera3D

@export var target_path: NodePath = NodePath("../chicken01")
@export var follow_offset := Vector3(0.0, 26.121084, 25.622486)
@export var spring_strength: float = 35.0
@export var spring_damping: float = 10.0

var _target: Node3D
var _velocity := Vector3.ZERO


func _ready() -> void:
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
