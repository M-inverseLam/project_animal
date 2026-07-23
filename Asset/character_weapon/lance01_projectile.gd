extends Node3D

@export var speed: float = 18.0
@export var lifetime: float = 2.0
@export var hit_spark_scene: PackedScene
@export var hit_spark_height: float = 0.8

@onready var hit_area := get_node_or_null("Area3D") as Area3D

var _direction := Vector3.FORWARD
var _damage := 1
var _source: Node
var _hit_targets: Array[Node] = []


func _ready() -> void:
	if hit_area != null:
		hit_area.body_entered.connect(_on_hit_body_entered)
		hit_area.area_entered.connect(_on_hit_area_entered)

	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)


func setup(direction: Vector3, damage: int, source: Node = null) -> void:
	if direction != Vector3.ZERO:
		_direction = direction.normalized()
	_damage = damage
	_source = source
	global_transform = Transform3D(_basis_with_y_axis(_direction), global_position)


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta


func _on_hit_body_entered(body: Node3D) -> void:
	_apply_hit(body)


func _on_hit_area_entered(area: Area3D) -> void:
	_apply_hit(area)


func _apply_hit(target: Node) -> void:
	if target == null:
		return
	if target == self or target == _source:
		return
	if _source != null and (target.is_ancestor_of(_source) or _source.is_ancestor_of(target)):
		return
	if _hit_targets.has(target):
		return

	_hit_targets.append(target)
	if target.has_method("take_attack_hit"):
		target.call("take_attack_hit", _direction, _damage)
		_spawn_hit_spark(target)
		queue_free()
	elif target.has_method("take_damage"):
		target.call("take_damage", _damage)
		_spawn_hit_spark(target)
		queue_free()


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
