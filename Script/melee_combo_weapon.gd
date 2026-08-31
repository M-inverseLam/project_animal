extends Node3D

@export var damage: int = 1
@export var impact_weight: float = 1.0
@export var attack_animation_name: StringName = &"slash"
@export var fallback_lifetime: float = 0.5
@export var ignored_groups: PackedStringArray = PackedStringArray(["enemy_projectile"])
@export var hit_spark_scene: PackedScene
@export_range(-10.0, 10.0, 0.1, "suffix:m") var hit_spark_height: float = 0.8

@export_group("Hit Collision")
@export_range(0.0, 1.0, 0.01, "suffix:s") var collision_cooldown_time: float = 0.05

@export_group("Hit Overlay")
@export var hit_overlay_enabled: bool = true
@export var hit_overlay_color: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var hit_overlay_power: float = 1.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var hit_overlay_duration: float = 0.12

@export_group("")

@onready var hit_area := find_child("Area3D", true, false) as Area3D
@onready var animation_player := _find_animation_player(self)

var _source: Node
var _attack_direction := Vector3.FORWARD
var _hit_stop_duration := 0.1
var _collision_is_enabled := true
var _collision_cooldown_time_left := 0.0
var _hit_targets: Dictionary = {}
var _hit_stop_time_left := 0.0
var _animation_was_playing_before_hit_stop := false
var _paused_animation_name := StringName()
var _paused_animation_position := 0.0


func _ready() -> void:
	if hit_area != null:
		hit_area.body_entered.connect(_on_hit_target)
		hit_area.area_entered.connect(_on_hit_target)

	if animation_player != null and animation_player.has_animation(attack_animation_name):
		animation_player.play(attack_animation_name)
		animation_player.animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
	else:
		get_tree().create_timer(maxf(fallback_lifetime, 0.01)).timeout.connect(queue_free)


func setup(
	source: Node,
	attack_direction: Vector3,
	hit_stop_duration: float = 0.1,
	knockback_power: float = 1.0
) -> void:
	_source = source
	_hit_stop_duration = maxf(hit_stop_duration, 0.0)
	impact_weight = maxf(knockback_power, 0.0)
	if not attack_direction.is_zero_approx():
		_attack_direction = attack_direction.normalized()


func _process(delta: float) -> void:
	_update_collision_cooldown(maxf(delta, 0.0))

	if _hit_stop_time_left <= 0.0:
		return

	_hit_stop_time_left = maxf(_hit_stop_time_left - maxf(delta, 0.0), 0.0)
	if _hit_stop_time_left <= 0.0 and _animation_was_playing_before_hit_stop:
		_animation_was_playing_before_hit_stop = false
		if animation_player != null:
			animation_player.play(_paused_animation_name)
			animation_player.seek(_paused_animation_position, true)
		_paused_animation_name = StringName()
		_paused_animation_position = 0.0


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result

	return null


func _on_hit_target(target: Node) -> void:
	if not _collision_is_enabled:
		return
	if target == null or target == self or target == _source:
		return
	if _source != null and (target.is_ancestor_of(_source) or _source.is_ancestor_of(target)):
		return
	if _is_ignored_target(target):
		return

	var damage_target := _find_damage_target(target)
	if damage_target == null:
		return
	var target_id := damage_target.get_instance_id()
	if _hit_targets.has(target_id):
		return

	_hit_targets[target_id] = true
	if damage_target.has_method("take_attack_hit"):
		damage_target.call("take_attack_hit", _attack_direction, damage, impact_weight)
	else:
		damage_target.call("take_damage", damage)
	if damage_target.has_method("start_melee_hit_stop"):
		damage_target.call("start_melee_hit_stop", _hit_stop_duration)
	_apply_hit_overlay(damage_target)
	_spawn_hit_spark(target)
	_start_hit_stop()
	_start_collision_cooldown()


func _start_collision_cooldown() -> void:
	_set_hit_collision_enabled(false)
	_collision_cooldown_time_left = maxf(collision_cooldown_time, 0.0)
	if _collision_cooldown_time_left <= 0.0:
		call_deferred("_set_hit_collision_enabled", true)


func _update_collision_cooldown(delta: float) -> void:
	if _collision_is_enabled or _collision_cooldown_time_left <= 0.0:
		return

	_collision_cooldown_time_left = maxf(_collision_cooldown_time_left - delta, 0.0)
	if _collision_cooldown_time_left <= 0.0:
		_set_hit_collision_enabled(true)


func _set_hit_collision_enabled(is_enabled: bool) -> void:
	_collision_is_enabled = is_enabled
	if hit_area != null:
		hit_area.set_deferred("monitoring", is_enabled)


func _apply_hit_overlay(damage_target: Node) -> void:
	if not hit_overlay_enabled or not damage_target.has_method("play_hit_overlay"):
		return
	damage_target.call(
		"play_hit_overlay",
		hit_overlay_color,
		maxf(hit_overlay_duration, 0.0),
		clampf(hit_overlay_power, 0.0, 1.0)
	)


func _start_hit_stop() -> void:
	var duration := _hit_stop_duration
	if duration <= 0.0:
		return

	_hit_stop_time_left = maxf(_hit_stop_time_left, duration)
	if animation_player != null and animation_player.is_playing() and not _animation_was_playing_before_hit_stop:
		_animation_was_playing_before_hit_stop = true
		_paused_animation_name = animation_player.current_animation
		_paused_animation_position = animation_player.current_animation_position
		animation_player.pause()
	if _source != null and _source.has_method("start_melee_hit_stop"):
		_source.call("start_melee_hit_stop", duration)


func _spawn_hit_spark(hit_target: Node) -> void:
	if hit_spark_scene == null or not hit_target is Node3D:
		return

	var hit_spark := hit_spark_scene.instantiate() as Node3D
	if hit_spark == null:
		return

	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		spawn_parent = get_tree().root
	spawn_parent.add_child(hit_spark)
	hit_spark.global_position = (hit_target as Node3D).global_position + Vector3.UP * hit_spark_height

	var longest_lifetime := _restart_particles_recursive(hit_spark)
	hit_spark.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(hit_spark.queue_free)


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


func _find_damage_target(target: Node) -> Node:
	var current := target
	while current != null:
		if current.has_method("take_attack_hit") or current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null


func _is_ignored_target(target: Node) -> bool:
	var current := target
	while current != null:
		for group_name in ignored_groups:
			if current.is_in_group(group_name):
				return true
		current = current.get_parent()
	return false


func _on_animation_finished(_animation_name: StringName) -> void:
	queue_free()
