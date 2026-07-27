extends Node3D

@export var speed: float = 10.0
@export var lifetime: float = 3.0
@export var keep_level: bool = true
@export var damage: int = 1
@export var hit_activation_delay: float = 0.35
@export var ignored_root_names: PackedStringArray = PackedStringArray(["bee01"])
@export var ignored_script_paths: PackedStringArray = PackedStringArray(["res://Script/enemy_Ai01.gd"])

@onready var hit_area := get_node_or_null("Area3D") as Area3D

var _direction := Vector3.FORWARD
var _source: Node
var _hit_targets: Array[Node] = []
var _hit_area_is_active := false


func _ready() -> void:
	if hit_area != null:
		hit_area.monitoring = false
		hit_area.body_entered.connect(_on_hit_body_entered)
		hit_area.area_entered.connect(_on_hit_area_entered)

	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)


func setup(direction: Vector3, source: Node = null) -> void:
	if direction != Vector3.ZERO:
		if keep_level:
			direction.y = 0.0
			if direction == Vector3.ZERO:
				direction = Vector3.FORWARD
		_direction = direction.normalized()
	_source = source
	_activate_hit_area_after_delay()


func _physics_process(delta: float) -> void:
	if keep_level:
		_direction.y = 0.0
		_direction = _direction.normalized()
	global_position += _direction * speed * delta


func _on_hit_body_entered(body: Node3D) -> void:
	_apply_hit(body)


func _on_hit_area_entered(area: Area3D) -> void:
	_apply_hit(area)


func _apply_hit(target: Node) -> void:
	if not _hit_area_is_active:
		return
	if target == null:
		return
	if target == self:
		return
	if _is_source_related(target):
		return
	if _is_ignored_target(target):
		return
	var forwarded_target := _get_forwarded_damage_target(target)
	if forwarded_target != null and _is_ignored_target(forwarded_target):
		return
	if _hit_targets.has(target):
		return

	_hit_targets.append(target)
	if target.has_method("take_damage"):
		target.call("take_damage", damage)
		queue_free()
	elif target.has_method("take_attack_hit"):
		target.call("take_attack_hit", _direction, damage)
		queue_free()


func _is_source_related(target: Node) -> bool:
	if _source == null:
		return false
	if target == _source:
		return true
	if target.is_ancestor_of(_source) or _source.is_ancestor_of(target):
		return true

	var current := target.get_parent()
	while current != null:
		if current == _source:
			return true
		current = current.get_parent()

	return false


func _is_ignored_target(target: Node) -> bool:
	var current := target
	while current != null:
		if ignored_root_names.has(current.name):
			return true
		var script := current.get_script() as Script
		if script != null and ignored_script_paths.has(script.resource_path):
			return true
		current = current.get_parent()

	return false


func _get_forwarded_damage_target(target: Node) -> Node:
	for property in target.get_property_list():
		if property.get("name", "") == "damage_target":
			var damage_target: Variant = target.get("damage_target")
			if damage_target is Node:
				return damage_target as Node
			return null

	return null


func _activate_hit_area_after_delay() -> void:
	if hit_area == null:
		return

	if hit_activation_delay <= 0.0:
		_set_hit_area_active(true)
		return

	get_tree().create_timer(hit_activation_delay).timeout.connect(_on_hit_activation_delay_finished)


func _on_hit_activation_delay_finished() -> void:
	_set_hit_area_active(true)


func _set_hit_area_active(is_active: bool) -> void:
	_hit_area_is_active = is_active
	if hit_area != null:
		hit_area.monitoring = is_active
