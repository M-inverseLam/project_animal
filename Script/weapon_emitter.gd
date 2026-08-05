class_name WeaponEmitter
extends Node3D

@export var projectile_scene: PackedScene

@export_group("Emission")
@export var shoot_interval_time: float = 0.5
@export var emit_quantity: int = 1
@export var emit_each_projectile_offset_time: float = 0.1
@export var muzzle_path: NodePath = NodePath("Muzzle")

@export_group("Dash")
@export var dash_duration: float = 0.5
@export var dash_distance: float = 5.0
@export var dash_damage: int = 1
@export var dash_slowdown_power: float = 2.5
@export var dash_bounce_back_distance: float = 1.4
@export var dash_bounce_back_duration: float = 0.25
@export var dash_bounce_back_slowdown_power: float = 2.5

@onready var muzzle := get_node_or_null(muzzle_path) as Marker3D

var _source: Node
var _shoot_direction := Vector3.FORWARD
var _is_firing := false
var _shoot_time_left := 0.0
var _burst_projectiles_remaining := 0
var _burst_emit_time_left := 0.0


func _physics_process(delta: float) -> void:
	if not _is_firing:
		return

	_shoot_time_left -= delta
	if _burst_projectiles_remaining > 0:
		_burst_emit_time_left -= delta
		_emit_due_projectiles()

	if _burst_projectiles_remaining <= 0 and _shoot_time_left <= 0.0:
		_burst_projectiles_remaining = maxi(emit_quantity, 1)
		_burst_emit_time_left = 0.0
		_shoot_time_left += maxf(shoot_interval_time, 0.01)
		_emit_due_projectiles()


func start_firing(source: Node) -> void:
	_source = source
	_is_firing = true


func stop_firing() -> void:
	_is_firing = false
	reset_firing()


func reset_firing() -> void:
	_shoot_time_left = 0.0
	_burst_projectiles_remaining = 0
	_burst_emit_time_left = 0.0


func set_shoot_direction(direction: Vector3) -> void:
	if not direction.is_zero_approx():
		_shoot_direction = direction.normalized()


func get_muzzle_global_position() -> Vector3:
	if muzzle != null:
		return muzzle.global_position
	return global_position


func _emit_due_projectiles() -> void:
	while _burst_projectiles_remaining > 0 and _burst_emit_time_left <= 0.0:
		_spawn_projectile()
		_burst_projectiles_remaining -= 1
		if _burst_projectiles_remaining <= 0:
			return
		if emit_each_projectile_offset_time > 0.0:
			_burst_emit_time_left += emit_each_projectile_offset_time


func _spawn_projectile() -> void:
	if projectile_scene == null:
		return

	var projectile := projectile_scene.instantiate() as Node3D
	if projectile == null:
		return

	var projectile_parent := get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_parent()
	if projectile_parent == null:
		projectile_parent = self

	projectile_parent.add_child(projectile)
	projectile.global_transform = Transform3D(
		_basis_with_y_axis(_shoot_direction),
		get_muzzle_global_position()
	)

	if projectile.has_method("setup"):
		projectile.call("setup", _shoot_direction, _source)


func _basis_with_y_axis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper_axis := Vector3.UP
	if absf(y_axis.dot(helper_axis)) > 0.98:
		helper_axis = Vector3.RIGHT

	var x_axis := helper_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
