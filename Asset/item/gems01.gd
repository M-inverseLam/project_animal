extends Node3D

@export var pop_height: float = 2.0
@export var pop_distance: float = 0.8
@export var rise_duration: float = 0.18
@export var fall_duration: float = 0.32
@export var bounce_height: float = 0.22
@export var bounce_duration: float = 0.16
@export var spin_turns: float = 1.5

var _rng := RandomNumberGenerator.new()
var _motion_tween: Tween
var _spin_tween: Tween


func _ready() -> void:
	_rng.randomize()


func pop_from_ground(spawn_position: Vector3) -> void:
	global_position = spawn_position

	if _motion_tween != null:
		_motion_tween.kill()
	if _spin_tween != null:
		_spin_tween.kill()

	var direction := _get_random_ground_direction()
	var start_position := global_position
	var land_position := start_position + direction * pop_distance
	var peak_position := start_position.lerp(land_position, 0.45) + Vector3.UP * pop_height
	var bounce_position := land_position + Vector3.UP * bounce_height

	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_SINE)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "global_position", peak_position, rise_duration)
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(self, "global_position", land_position, fall_duration)
	_motion_tween.set_trans(Tween.TRANS_SINE)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "global_position", bounce_position, bounce_duration * 0.45)
	_motion_tween.set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(self, "global_position", land_position, bounce_duration * 0.55)

	_spin_tween = create_tween()
	_spin_tween.tween_property(self, "rotation:y", rotation.y + TAU * spin_turns, rise_duration + fall_duration + bounce_duration)


func _get_random_ground_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()
