class_name MeleeComboEmitter
extends Node3D

@export_group("Melee Combo")
@export var combo_attacks: Array[HeroComboAttack] = []
@export_range(0.0, 2.0, 0.01, "suffix:s") var combo_continue_time: float = 0.3
@export_range(0.0, 1.0, 0.01, "suffix:s") var hit_stop_time: float = 0.1

@export_group("Dash")
@export_range(0.0, 100.0, 0.1, "suffix:m/s") var dash_speed: float = 10.0
@export_range(0.0, 5.0, 0.01, "suffix:s") var dash_time: float = 0.5
## X is normalized dash time and Y is normalized speed from 0 to 1.
@export var dash_speed_curve: Curve

var _next_combo_index := 0


func take_next_combo_attack(hero_animation_player: AnimationPlayer) -> HeroComboAttack:
	if combo_attacks.is_empty() or hero_animation_player == null:
		return null

	for offset in range(combo_attacks.size()):
		var combo_index := (_next_combo_index + offset) % combo_attacks.size()
		var combo := combo_attacks[combo_index]
		if combo == null or combo.animation_name.is_empty():
			continue
		if not hero_animation_player.has_animation(combo.animation_name):
			continue

		_next_combo_index = (combo_index + 1) % combo_attacks.size()
		return combo

	return null


func get_valid_combo_animation_names(hero_animation_player: AnimationPlayer) -> PackedStringArray:
	var valid_names := PackedStringArray()
	if hero_animation_player == null:
		return valid_names

	for combo in combo_attacks:
		if combo == null or combo.animation_name.is_empty():
			continue
		var animation_name := String(combo.animation_name)
		if hero_animation_player.has_animation(combo.animation_name) and not valid_names.has(animation_name):
			valid_names.append(animation_name)

	return valid_names


func is_combo_animation(animation_name: String) -> bool:
	for combo in combo_attacks:
		if combo != null and String(combo.animation_name) == animation_name:
			return true
	return false


func is_end_combo(combo: HeroComboAttack, hero_animation_player: AnimationPlayer) -> bool:
	if combo == null or hero_animation_player == null:
		return true

	var last_valid_combo: HeroComboAttack
	for candidate in combo_attacks:
		if candidate == null or candidate.animation_name.is_empty():
			continue
		if hero_animation_player.has_animation(candidate.animation_name):
			last_valid_combo = candidate

	return combo == last_valid_combo


func spawn_combo_weapon(combo: HeroComboAttack, source: Node, attack_direction: Vector3) -> Node3D:
	if combo == null or combo.weapon_scene == null:
		return null

	var weapon := combo.weapon_scene.instantiate() as Node3D
	if weapon == null:
		return null

	add_child(weapon)
	if weapon.has_method("setup"):
		weapon.call("setup", source, attack_direction, hit_stop_time)
	return weapon


func reset_combo_cycle() -> void:
	_next_combo_index = 0
