extends Node3D

@export var pickup_effect_scene: PackedScene
@export var gem_value: int = 2
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
var _is_picked_up := false

@onready var pickup_area := get_node_or_null("PickupArea") as Area3D


func _ready() -> void:
	_rng.randomize()
	if pickup_area != null:
		pickup_area.body_entered.connect(_on_pickup_area_body_entered)


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


func _on_pickup_area_body_entered(body: Node3D) -> void:
	if _is_picked_up:
		return
	if not _is_hero_body(body):
		return

	_is_picked_up = true
	_add_gems_to_ui()
	_spawn_pickup_effect()
	queue_free()


func _is_hero_body(body: Node) -> bool:
	if body.name == "hero_girl01":
		return true

	var script := body.get_script() as Script
	return script != null and script.resource_path == "res://Script/hero01.gd"


func _add_gems_to_ui() -> void:
	var gems_total_label := _find_gems_total_label()
	if gems_total_label == null:
		return

	var current_total := gems_total_label.text.to_int()
	gems_total_label.text = str(current_total + gem_value)


func _find_gems_total_label() -> Label:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null

	var label := scene_root.get_node_or_null("Interface/ui04_main/MarginContainer/HBoxContainer/gemstotal") as Label
	if label != null:
		return label

	return scene_root.find_child("gemstotal", true, false) as Label


func _spawn_pickup_effect() -> void:
	if pickup_effect_scene == null:
		return

	var pickup_effect := pickup_effect_scene.instantiate() as Node3D
	if pickup_effect == null:
		return

	var effect_parent := get_tree().current_scene
	if effect_parent == null:
		effect_parent = get_parent()
	if effect_parent == null:
		return

	effect_parent.add_child(pickup_effect)
	pickup_effect.global_position = global_position

	var longest_lifetime := _restart_particles_recursive(pickup_effect)
	pickup_effect.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(pickup_effect.queue_free)


func _restart_particles_recursive(node: Node) -> float:
	var longest_lifetime := 1.0

	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.restart()
		particles.emitting = true
		longest_lifetime = maxf(longest_lifetime, particles.lifetime)

	for child in node.get_children():
		longest_lifetime = maxf(longest_lifetime, _restart_particles_recursive(child))

	return longest_lifetime
