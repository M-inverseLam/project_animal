extends Node3D

@export var max_health: int = 3

@onready var visual_root := get_node_or_null("mouse01") as Node3D

var health := 0
var _visual_start_scale := Vector3.ONE
var _hit_tween: Tween


func _ready() -> void:
	health = max_health
	if visual_root != null:
		_visual_start_scale = visual_root.scale


func take_damage(damage: int) -> void:
	health = maxi(health - damage, 0)
	print("mouse01 took ", damage, " damage. HP: ", health, "/", max_health)
	_play_hit_feedback()

	if health <= 0:
		queue_free()


func _play_hit_feedback() -> void:
	if visual_root == null:
		return

	if _hit_tween != null:
		_hit_tween.kill()

	_hit_tween = create_tween()
	var hit_scale := Vector3(_visual_start_scale.x * 1.2, _visual_start_scale.y * 0.75, _visual_start_scale.z * 1.2)
	_hit_tween.tween_property(visual_root, "scale", hit_scale, 0.06)
	_hit_tween.tween_property(visual_root, "scale", _visual_start_scale, 0.12)
