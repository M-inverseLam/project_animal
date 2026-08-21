class_name HeroComboAttack
extends Resource

@export var animation_name: StringName
@export var weapon_scene: PackedScene
@export_range(0.0, 100.0, 0.1, "suffix:m/s") var move_speed: float = 5.0
@export_range(0.0, 10.0, 0.01, "suffix:s") var move_time: float = 0.2
## X is normalized movement time and Y is movement speed. The curve is normalized
## automatically across Move Time. Total distance is Move Speed multiplied by Move Time.
@export var movement_speed_curve: Curve
