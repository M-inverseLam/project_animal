class_name WeaponEmitter
extends Node3D

@export var projectile_scene: PackedScene

@export_group("Emission")
@export var shoot_interval_time: float = 0.5
@export var emit_quantity: int = 1
@export var emit_each_projectile_offset_time: float = 0.1
@export var muzzle_paths: Array[NodePath] = [NodePath("Muzzle")]

@export_group("Dash")
@export var dash_duration: float = 0.5
@export var dash_distance: float = 5.0
@export var dash_damage: int = 1
@export var dash_slowdown_power: float = 2.5
@export var dash_bounce_back_distance: float = 1.4
@export var dash_bounce_back_duration: float = 0.25
@export var dash_bounce_back_slowdown_power: float = 2.5

var _source: Node
var _shoot_direction := Vector3.FORWARD
var _is_firing := false
var _shoot_time_left := 0.0
var _burst_projectiles_remaining := 0
var _burst_emit_time_left := 0.0
var _muzzles: Array[Marker3D] = []
var _next_muzzle_index := 0


func _ready() -> void:
	_cache_muzzles()


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


func pause_firing() -> void:
	_is_firing = false


func reset_firing() -> void:
	_shoot_time_left = 0.0
	_burst_projectiles_remaining = 0
	_burst_emit_time_left = 0.0
	_next_muzzle_index = 0


func set_shoot_direction(direction: Vector3) -> void:
	if not direction.is_zero_approx():
		_shoot_direction = direction.normalized()


func get_muzzle_global_position(muzzle_index: int = 0) -> Vector3:
	var selected_muzzle := _get_muzzle(muzzle_index)
	if selected_muzzle != null:
		return selected_muzzle.global_position
	return global_position


func get_muzzle_shoot_direction(muzzle_index: int = 0) -> Vector3:
	var selected_muzzle := _get_muzzle(muzzle_index)
	if selected_muzzle == null:
		return _shoot_direction

	var emitter_basis := global_transform.basis.orthonormalized()
	var muzzle_basis := selected_muzzle.global_transform.basis.orthonormalized()
	var local_aim_direction := emitter_basis.inverse() * _shoot_direction
	var muzzle_direction := muzzle_basis * local_aim_direction
	if muzzle_direction.is_zero_approx():
		return _shoot_direction
	return muzzle_direction.normalized()


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

	var muzzle_index := _take_next_muzzle_index()
	var emission_direction := get_muzzle_shoot_direction(muzzle_index)
	projectile_parent.add_child(projectile)
	projectile.global_transform = Transform3D(
		_basis_with_y_axis(emission_direction),
		get_muzzle_global_position(muzzle_index)
	)

	if projectile.has_method("setup"):
		projectile.call("setup", emission_direction, _source)


func _cache_muzzles() -> void:
	_muzzles.clear()
	for path in muzzle_paths:
		var selected_muzzle := get_node_or_null(path) as Marker3D
		if selected_muzzle != null and not _muzzles.has(selected_muzzle):
			_muzzles.append(selected_muzzle)


func _get_muzzle(muzzle_index: int) -> Marker3D:
	if _muzzles.is_empty():
		return null
	return _muzzles[posmod(muzzle_index, _muzzles.size())]


func _take_next_muzzle_index() -> int:
	if _muzzles.is_empty():
		return 0

	var muzzle_index := _next_muzzle_index
	_next_muzzle_index = (_next_muzzle_index + 1) % _muzzles.size()
	return muzzle_index


func _basis_with_y_axis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper_axis := Vector3.UP
	if absf(y_axis.dot(helper_axis)) > 0.98:
		helper_axis = Vector3.RIGHT

	var x_axis := helper_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
