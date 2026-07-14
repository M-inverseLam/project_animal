extends StaticBody3D

@export var damage_target_path: NodePath = NodePath("..")

@onready var damage_target := get_node_or_null(damage_target_path)


func take_damage(damage: int) -> void:
	if damage_target != null and damage_target.has_method("take_damage"):
		damage_target.call("take_damage", damage)
