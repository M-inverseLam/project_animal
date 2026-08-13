extends Node3D

enum MovementMode {
	STRAIGHT,
	EXPANDING_SPIRAL,
}

@export_group("Movement")
@export var movement_mode: MovementMode = MovementMode.STRAIGHT
@export var speed: float = 18.0

@export_subgroup("Expanding Spiral")
@export_range(0.0, 100.0, 0.01, "suffix:m") var spiral_initial_radius: float = 0.0
@export_range(0.0, 100.0, 0.01, "suffix:m/s") var spiral_radius_growth_speed: float = 3.0
@export_range(0.0, 3600.0, 1.0, "suffix:deg/s") var spiral_angular_speed_degrees: float = 360.0
@export var spiral_clockwise: bool = false
@export var spiral_follow_hero_position: bool = false

@export_group("")
@export var lifetime: float = 2.0
@export var damage: int = 1
@export var impact_weight: float = 1.0

@export_group("Weapon Health")
@export_range(1, 100, 1) var weapon_health: int = 1
@export_range(0.0, 10.0, 0.01, "suffix:s") var collision_cooldown_time: float = 0.1

@export_group("")
@export var hit_spark_scene: PackedScene
@export var hit_spark_height: float = 0.8
@export var ignored_groups: PackedStringArray = PackedStringArray(["enemy_projectile"])

@export_group("Hit Camera Shake")
@export var hit_camera_shake_enabled: bool = false

@onready var hit_area := get_node_or_null("Area3D") as Area3D

var _direction := Vector3.FORWARD
var _source: Node
var _is_active := false
var _collision_is_enabled := false
var _current_health := 0
var _spiral_center := Vector3.ZERO
var _spiral_radial_direction := Vector3.FORWARD
var _spiral_elapsed := 0.0
var _spiral_previous_source_position := Vector3.ZERO
var _spiral_has_source_position := false


func _ready() -> void:
	_current_health = maxi(weapon_health, 1)
	if hit_area != null:
		hit_area.body_entered.connect(_on_hit_body_entered)
		hit_area.area_entered.connect(_on_hit_area_entered)

	_activate_projectile()


func setup(direction: Vector3, source: Node = null) -> void:
	if direction != Vector3.ZERO:
		_direction = direction.normalized()
	_source = source
	global_transform = Transform3D(_basis_with_y_axis(_direction), global_position)
	_initialize_spiral_motion()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	if movement_mode == MovementMode.EXPANDING_SPIRAL:
		_process_expanding_spiral(delta)
	else:
		global_position += _direction * speed * delta


func _initialize_spiral_motion() -> void:
	_spiral_elapsed = 0.0
	_spiral_radial_direction = Vector3(_direction.x, 0.0, _direction.z)
	if _spiral_radial_direction.is_zero_approx():
		_spiral_radial_direction = Vector3.FORWARD
	else:
		_spiral_radial_direction = _spiral_radial_direction.normalized()

	var initial_radius := maxf(spiral_initial_radius, 0.0)
	_spiral_center = global_position - _spiral_radial_direction * initial_radius
	_spiral_has_source_position = spiral_follow_hero_position and _source is Node3D and is_instance_valid(_source)
	if _spiral_has_source_position:
		_spiral_previous_source_position = (_source as Node3D).global_position


func _process_expanding_spiral(delta: float) -> void:
	_update_spiral_center_from_source()
	_spiral_elapsed += maxf(delta, 0.0)
	var turn_direction := -1.0 if spiral_clockwise else 1.0
	var angle := deg_to_rad(spiral_angular_speed_degrees) * _spiral_elapsed * turn_direction
	var radius := maxf(spiral_initial_radius, 0.0) + maxf(spiral_radius_growth_speed, 0.0) * _spiral_elapsed
	var radial_direction := _spiral_radial_direction.rotated(Vector3.UP, angle)
	var next_position := _spiral_center + radial_direction * radius
	var frame_direction := next_position - global_position

	global_position = next_position
	if not frame_direction.is_zero_approx():
		_direction = frame_direction.normalized()
		global_transform = Transform3D(_basis_with_y_axis(_direction), global_position)


func _update_spiral_center_from_source() -> void:
	if not spiral_follow_hero_position:
		_spiral_has_source_position = false
		return
	if not (_source is Node3D) or not is_instance_valid(_source):
		_spiral_has_source_position = false
		return

	var source_position := (_source as Node3D).global_position
	if _spiral_has_source_position:
		_spiral_center += source_position - _spiral_previous_source_position
	_spiral_previous_source_position = source_position
	_spiral_has_source_position = true


func _on_hit_body_entered(body: Node3D) -> void:
	_apply_hit(body)


func _on_hit_area_entered(area: Area3D) -> void:
	_apply_hit(area)


func _apply_hit(target: Node) -> void:
	if not _is_active or not _collision_is_enabled:
		return
	if target == null:
		return
	if target == self or target == _source:
		return
	if _source != null and (target.is_ancestor_of(_source) or _source.is_ancestor_of(target)):
		return
	if _is_ignored_target(target):
		return

	var hit_was_applied := false
	if target.has_method("take_attack_hit"):
		target.call("take_attack_hit", _direction, damage, impact_weight)
		hit_was_applied = true
	elif target.has_method("take_damage"):
		target.call("take_damage", damage)
		hit_was_applied = true

	if not hit_was_applied:
		return

	_spawn_hit_spark(target)
	_shake_camera_on_hit()
	_consume_weapon_health()


func _consume_weapon_health() -> void:
	_current_health = maxi(_current_health - 1, 0)
	_set_collision_enabled(false)
	if _current_health <= 0:
		queue_free()
		return

	if collision_cooldown_time <= 0.0:
		call_deferred("_restore_collision")
		return

	get_tree().create_timer(collision_cooldown_time).timeout.connect(_restore_collision)


func _restore_collision() -> void:
	if not _is_active or _current_health <= 0:
		return
	_set_collision_enabled(true)


func _is_ignored_target(target: Node) -> bool:
	var current := target
	while current != null:
		for group_name in ignored_groups:
			if current.is_in_group(group_name):
				return true
		current = current.get_parent()

	return false


func _activate_projectile() -> void:
	_set_projectile_active(true)

	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _set_projectile_active(is_active: bool) -> void:
	_is_active = is_active
	visible = is_active
	_set_collision_enabled(is_active)


func _set_collision_enabled(is_enabled: bool) -> void:
	_collision_is_enabled = is_enabled
	if hit_area != null:
		hit_area.set_deferred("monitoring", is_enabled)


func _spawn_hit_spark(target: Node) -> void:
	if hit_spark_scene == null:
		return

	var hit_spark := hit_spark_scene.instantiate() as Node3D
	if hit_spark == null:
		return

	var spark_parent := get_tree().current_scene
	if spark_parent == null:
		spark_parent = get_parent()
	if spark_parent == null:
		return

	spark_parent.add_child(hit_spark)
	if target is Node3D:
		hit_spark.global_position = (target as Node3D).global_position + Vector3.UP * hit_spark_height
	else:
		hit_spark.global_position = global_position

	var longest_lifetime := _restart_particles_recursive(hit_spark)
	hit_spark.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(hit_spark.queue_free)


func _shake_camera_on_hit() -> void:
	if not hit_camera_shake_enabled:
		return

	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake_camera"):
		camera.call("shake_camera")


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


func _basis_with_y_axis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper_axis := Vector3.UP
	if absf(y_axis.dot(helper_axis)) > 0.98:
		helper_axis = Vector3.RIGHT

	var x_axis := helper_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
