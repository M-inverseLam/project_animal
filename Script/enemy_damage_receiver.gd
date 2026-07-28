extends StaticBody3D

@export var damage_target_path: NodePath = NodePath("..")

@onready var damage_target := get_node_or_null(damage_target_path)


func take_damage(damage: int) -> void:
	if damage_target != null and damage_target.has_method("take_damage"):
		damage_target.call("take_damage", damage)


func take_attack_hit(direction: Vector3, damage: int) -> void:
	if damage_target != null and damage_target.has_method("take_attack_hit"):
		damage_target.call("take_attack_hit", direction, damage)


func take_dash_hit(direction: Vector3, damage: int) -> void:
	if damage_target != null and damage_target.has_method("take_dash_hit"):
		damage_target.call("take_dash_hit", direction, damage)
