extends CharacterBody3D

const MOUSE_AIM_PLANE_Y := 0.0

enum FaceControlMode {
	KEY_ARROW,
	MOUSE_CURSOR,
}

@export var move_speed: float = 4.0
@export var mouse_turn_speed: float = 12.0
@export var arrow_face_turn_speed: float = 4.0
@export var arrow_face_turn_step_degrees: float = 15.0
@export var animation_blend_time: float = 0.2
@export var slide_duration: float = 0.3

@export_group("Health")
@export var max_health: int = 500
@export var death_animation_name: String = "die"
@export var game_over_delay: float = 1.0
@export var hit_flash_duration: float = 0.25
@export var hit_flash_power: float = 0.5
@export var hit_flash_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var damage_camera_shake_duration: float = 0.2
@export var damage_camera_shake_strength: float = 0.15

@export_group("")

@export_group("Gem Pickup")
@export_range(0.1, 50.0, 0.1, "suffix:m") var gem_attraction_radius: float = 4.0

@export_group("")

@export_group("Attack")
@export var attack_animation_name: String = "attack01"
@export var attack_idle_animation_name: String = "attack_idle"
@export var attack_animation_cycle: PackedStringArray = PackedStringArray(["attack01", "attack02"])
@export var attack_projectile_scene: PackedScene
@export var attack_projectile_spawn_path: NodePath = NodePath("shootposition")
@export var attack_upper_body_bone_name: String = "spline1"
@export var attack_lower_body_bone_name: String = "pelvis"

@export_group("")

@export_group("Super Attack")
@export var super_attack_charge_animation_name: String = "superattack_charge"
@export var super_attack_shoot_animation_name: String = "superattack_shoot"
@export var super_attack_charge_time: float = 2.0
@export var super_attack_projectile_scene: PackedScene
@export var super_attack_charge_effect_scene: PackedScene
@export var super_attack_shoot_hit_spark_scene: PackedScene

@export_group("")

@export_group("Dash")
@export var dash_animation_name: String = "dash"
@export var dash_animation_cycle: PackedStringArray = PackedStringArray(["dash", "dash02"])
@export var dash_cooldown: float = 0.5
@export var dash_hit_camera_shake_duration: float = 0.5
@export var dash_hit_camera_shake_strength: float = 0.45
@export var dash_dust_scene: PackedScene
@export var dash_hit_spark_scene: PackedScene
@export var dash_hit_spark_height: float = 0.8

@export_group("")

@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
@onready var visual_root := get_node_or_null("hero_girl01") as Node3D
@onready var dash_dust_template := get_node_or_null("DashDust") as Node3D
@onready var attack_projectile_spawn := get_node_or_null(attack_projectile_spawn_path) as Node3D
@onready var dash_hitbox := get_node_or_null("DashHitbox") as Area3D
@onready var dash_hitbox_shape := get_node_or_null("DashHitbox/CollisionShape3D") as CollisionShape3D
@onready var gem_attraction_shape := get_node_or_null("GemAttractionArea/CollisionShape3D") as CollisionShape3D

var _current_animation := ""
var _animation_tree: AnimationTree
var _attack_animation_node_a: AnimationNodeAnimation
var _attack_animation_node_b: AnimationNodeAnimation
var _dash_animation_node: AnimationNodeAnimation
var _uses_animation_tree := false
var _runtime_idle_animation_name := ""
var _runtime_walk_animation_name := ""
var _runtime_dash_animation_name := ""
var _runtime_attack_idle_animation_name := ""
var _runtime_attack_animation_names := {}
var _locomotion_blend_amount := 0.0
var _target_locomotion_blend_amount := 0.0
var _dash_blend_amount := 0.0
var _target_dash_blend_amount := 0.0
var _upper_idle_blend_amount := 1.0
var _target_upper_idle_blend_amount := 1.0
var _attack_blend_amount := 0.0
var _target_attack_blend_amount := 0.0
var _attack_layer_blend_amount := 0.0
var _target_attack_layer_blend_amount := 0.0
var _active_attack_blend_slot := 0
var _current_health := 0
var _is_dead := false
var _game_over_was_scheduled := false
var _hit_flash_tween: Tween
var _hit_flash_material: StandardMaterial3D
var _hit_flash_meshes: Array[MeshInstance3D] = []
var _hit_flash_previous_overlays: Array[Material] = []
var _last_movement := Vector3.ZERO
var _slide_time_left := 0.0
var _attack_key_was_pressed := false
var _auto_shoot_is_enabled := true
var _resume_auto_shoot_after_dash := false
var _is_attacking := false
var _attack_time_left := 0.0
var _queued_attack_animation_name := ""
var _next_attack_animation_index := 0
var _attack_projectiles_emitted := 0
var _attack_projectile_emit_time_left := 0.0
var _is_super_attacking := false
var _super_attack_phase := ""
var _super_attack_time_left := 0.0
var _resume_auto_shoot_after_super := false
var _active_super_charge_effect: Node3D
var _dash_key_was_pressed := false
var _is_dashing := false
var _next_dash_animation_index := 0
var _dash_time_left := 0.0
var _dash_elapsed := 0.0
var _dash_distance_ratio := 0.0
var _dash_direction := Vector3.ZERO
var _is_dash_bouncing_back := false
var _dash_bounce_elapsed := 0.0
var _dash_bounce_distance_ratio := 0.0
var _dash_cooldown_time_left := 0.0
var _active_dash_dust: Node3D
var _dash_hit_targets: Array[Node] = []
var _weapon_dash_duration := 1.0
var _weapon_dash_distance := 5.0
var _weapon_dash_damage := 1
var _weapon_dash_slowdown_power := 4.0
var _weapon_dash_bounce_back_distance := 1.4
var _weapon_dash_bounce_back_duration := 0.25
var _weapon_dash_bounce_back_slowdown_power := 2.5
var _weapon_emit_quantity := 1
var _weapon_emit_projectile_offset_time := 0.1
var _mouse_world_position := Vector3.ZERO
var _face_control_mode: int = FaceControlMode.KEY_ARROW
var _face_control_toggle_was_pressed := false
var _last_keyboard_face_direction := Vector3.FORWARD
var _has_keyboard_face_target := false
var _keyboard_face_up_was_pressed := false
var _keyboard_face_down_was_pressed := false
var _keyboard_face_left_was_pressed := false
var _keyboard_face_right_was_pressed := false


func _ready() -> void:
	_face_control_mode = FaceControlMode.KEY_ARROW
	_has_keyboard_face_target = false
	_current_health = max_health
	_update_health_ui()
	_update_gem_attraction_radius()
	_cache_hit_flash_meshes()
	_load_weapon_parameters()
	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	_setup_animation_tree()
	if dash_hitbox != null:
		dash_hitbox.body_entered.connect(_on_dash_hitbox_body_entered)
		dash_hitbox.area_entered.connect(_on_dash_hitbox_area_entered)
	_set_dash_hitbox_enabled(false)
	_stop_dash_dust()
	_play_animation("idle")
	_start_attack()


func set_gem_attraction_radius(radius: float) -> void:
	gem_attraction_radius = maxf(radius, 0.1)
	_update_gem_attraction_radius()


func _update_gem_attraction_radius() -> void:
	if gem_attraction_shape == null:
		return

	var sphere := gem_attraction_shape.shape as SphereShape3D
	if sphere == null:
		return

	sphere.radius = gem_attraction_radius


func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector3.ZERO
		return
	if _is_super_attacking:
		_process_super_attack(delta)
		return

	_update_dash_cooldown(delta)
	_update_animation_tree_blends(delta)
	_update_attack_input()
	_update_face_direction_input(delta)
	_update_attack_projectile(delta)

	_update_dash_input()

	if _is_dashing:
		_process_dash(delta)
		return

	_process_locomotion(delta)


func _process_locomotion(delta: float) -> void:
	var input_movement := _get_keyboard_movement()
	var movement := input_movement
	var is_sliding := false

	if input_movement != Vector3.ZERO:
		_last_movement = input_movement
		_slide_time_left = slide_duration
	elif slide_duration > 0.0 and _slide_time_left > 0.0 and _last_movement != Vector3.ZERO:
		_slide_time_left = maxf(_slide_time_left - delta, 0.0)
		movement = _last_movement * (_slide_time_left / slide_duration)
		is_sliding = true
	else:
		_last_movement = Vector3.ZERO

	if movement != Vector3.ZERO:
		_move_with_collision(movement * move_speed * delta, delta)
		if not is_sliding:
			_play_animation("walk")
			return

	_play_animation("idle")


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != KEY_CTRL:
		return
	if key_event.location != KEY_LOCATION_RIGHT:
		return

	_start_super_attack()


func _get_keyboard_movement() -> Vector3:
	var direction := Vector3.ZERO

	if Input.is_physical_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0

	return direction.normalized()


func _update_attack_input() -> void:
	var attack_key_is_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if attack_key_is_pressed and not _attack_key_was_pressed:
		_auto_shoot_is_enabled = not _auto_shoot_is_enabled
		if _auto_shoot_is_enabled:
			_start_attack()

	if _auto_shoot_is_enabled and not _is_attacking:
		_start_attack()

	_attack_key_was_pressed = attack_key_is_pressed


func _update_dash_input() -> void:
	var dash_key_is_pressed := Input.is_physical_key_pressed(KEY_SPACE)

	if dash_key_is_pressed and not _dash_key_was_pressed:
		_start_dash()

	_dash_key_was_pressed = dash_key_is_pressed


func _update_dash_cooldown(delta: float) -> void:
	if _dash_cooldown_time_left > 0.0:
		_dash_cooldown_time_left = maxf(_dash_cooldown_time_left - delta, 0.0)


func _start_attack() -> void:
	if _is_dashing or _is_super_attacking:
		return

	if _is_attacking and _queued_attack_animation_name != "":
		return

	var selected_attack_animation := _get_next_attack_animation_name()
	if selected_attack_animation == "":
		return

	if _is_attacking:
		_queued_attack_animation_name = selected_attack_animation
		return

	_play_attack_animation(selected_attack_animation)


func _play_attack_animation(animation_name: String) -> void:
	_is_attacking = true
	_attack_time_left = _get_animation_length(animation_name)
	_attack_projectiles_emitted = 0
	_attack_projectile_emit_time_left = 0.0

	_play_animation(animation_name, true)


func _start_dash() -> void:
	if _is_super_attacking:
		return
	if _is_dashing:
		return
	if _dash_cooldown_time_left > 0.0:
		return

	var selected_dash_animation := _get_next_dash_animation_name()
	if selected_dash_animation == "":
		return

	_resume_auto_shoot_after_dash = _auto_shoot_is_enabled
	_clear_attack_state(true)
	_is_dashing = true
	_dash_time_left = _weapon_dash_duration
	_dash_elapsed = 0.0
	_dash_distance_ratio = 0.0
	_dash_direction = _get_dash_direction()
	_is_dash_bouncing_back = false
	_dash_bounce_elapsed = 0.0
	_dash_bounce_distance_ratio = 0.0
	_last_movement = _dash_direction
	_slide_time_left = 0.0
	_dash_hit_targets.clear()

	_set_dash_hitbox_enabled(true)
	_start_dash_dust()
	_play_animation(selected_dash_animation, true)


func _process_dash(delta: float) -> void:
	if _is_dash_bouncing_back:
		_process_dash_bounce_back(delta)
		return

	if _weapon_dash_duration <= 0.0 or _weapon_dash_distance <= 0.0:
		_stop_dash()
		return

	_dash_elapsed = minf(_dash_elapsed + delta, _weapon_dash_duration)
	var progress := _dash_elapsed / _weapon_dash_duration
	var slowdown_power := maxf(_weapon_dash_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _dash_distance_ratio) * _weapon_dash_distance

	_move_with_collision(_dash_direction * frame_distance, delta)
	_dash_distance_ratio = distance_ratio
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	_apply_current_dash_overlaps()

	if _dash_time_left <= 0.0:
		_stop_dash()


func _process_dash_bounce_back(delta: float) -> void:
	if _weapon_dash_bounce_back_duration <= 0.0 or _weapon_dash_bounce_back_distance <= 0.0:
		_stop_dash()
		return

	_dash_bounce_elapsed = minf(_dash_bounce_elapsed + delta, _weapon_dash_bounce_back_duration)
	var progress := _dash_bounce_elapsed / _weapon_dash_bounce_back_duration
	var slowdown_power := maxf(_weapon_dash_bounce_back_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _dash_bounce_distance_ratio) * _weapon_dash_bounce_back_distance

	_move_with_collision(-_dash_direction * frame_distance, delta)
	_dash_bounce_distance_ratio = distance_ratio

	if _dash_bounce_elapsed >= _weapon_dash_bounce_back_duration:
		_stop_dash()


func _stop_dash() -> void:
	_is_dashing = false
	_dash_time_left = 0.0
	_dash_elapsed = 0.0
	_dash_distance_ratio = 0.0
	_is_dash_bouncing_back = false
	_dash_bounce_elapsed = 0.0
	_dash_bounce_distance_ratio = 0.0
	_dash_hit_targets.clear()
	_set_dash_hitbox_enabled(false)
	_stop_dash_dust()
	_dash_cooldown_time_left = dash_cooldown
	_current_animation = ""
	_resume_auto_shoot(_resume_auto_shoot_after_dash)
	_resume_auto_shoot_after_dash = false


func _get_dash_direction() -> Vector3:
	var input_direction := _get_keyboard_movement()
	if input_direction != Vector3.ZERO:
		return input_direction

	return global_transform.basis.z.normalized()


func _load_weapon_parameters() -> void:
	if attack_projectile_scene == null:
		return

	var weapon: Node = attack_projectile_scene.instantiate()
	if weapon == null:
		return

	_weapon_dash_duration = _get_float_property(weapon, "dash_duration", _weapon_dash_duration)
	_weapon_dash_distance = _get_float_property(weapon, "dash_distance", _weapon_dash_distance)
	_weapon_dash_damage = _get_int_property(weapon, "dash_damage", _weapon_dash_damage)
	_weapon_dash_slowdown_power = _get_float_property(weapon, "dash_slowdown_power", _weapon_dash_slowdown_power)
	_weapon_dash_bounce_back_distance = _get_float_property(weapon, "dash_bounce_back_distance", _weapon_dash_bounce_back_distance)
	_weapon_dash_bounce_back_duration = _get_float_property(weapon, "dash_bounce_back_duration", _weapon_dash_bounce_back_duration)
	_weapon_dash_bounce_back_slowdown_power = _get_float_property(weapon, "dash_bounce_back_slowdown_power", _weapon_dash_bounce_back_slowdown_power)
	_weapon_emit_quantity = maxi(_get_int_property(weapon, "emit_quantity", _weapon_emit_quantity), 1)
	_weapon_emit_projectile_offset_time = maxf(_get_float_property(weapon, "emit_each_projectile_offset_time", _weapon_emit_projectile_offset_time), 0.0)
	weapon.free()


func _get_float_property(object: Object, property_name: String, fallback: float) -> float:
	if not _has_property(object, property_name):
		return fallback

	var value: Variant = object.get(property_name)
	if value is float or value is int:
		return float(value)

	return fallback


func _get_int_property(object: Object, property_name: String, fallback: int) -> int:
	if not _has_property(object, property_name):
		return fallback

	var value: Variant = object.get(property_name)
	if value is int:
		return int(value)
	if value is float:
		return int(value)

	return fallback


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.get("name", "") == property_name:
			return true

	return false


func _move_with_collision(displacement: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return

	velocity = displacement / delta
	velocity.y = 0.0
	move_and_slide()
	velocity = Vector3.ZERO


func take_damage(damage: int) -> void:
	if damage <= 0 or _is_dead:
		return

	var previous_health: int = _current_health
	_current_health = maxi(_current_health - damage, 0)
	_update_health_ui()
	_play_hit_flash()
	_shake_camera_on_damage()
	if previous_health > 0 and _current_health == 0:
		_start_death()


func _cache_hit_flash_meshes() -> void:
	_hit_flash_meshes.clear()
	_hit_flash_previous_overlays.clear()
	if visual_root == null:
		return

	for child in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		_hit_flash_meshes.append(mesh_instance)
		_hit_flash_previous_overlays.append(mesh_instance.material_overlay)


func _play_hit_flash() -> void:
	if hit_flash_duration <= 0.0 or _hit_flash_meshes.is_empty():
		return

	if _hit_flash_material == null:
		_hit_flash_material = StandardMaterial3D.new()
		_hit_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if _hit_flash_tween != null:
		_hit_flash_tween.kill()

	var flash_color := hit_flash_color
	flash_color.a = clampf(hit_flash_power, 0.0, 1.0)
	_hit_flash_material.albedo_color = flash_color
	for mesh_instance in _hit_flash_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _hit_flash_material

	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash_material, "albedo_color:a", 0.0, hit_flash_duration)
	_hit_flash_tween.tween_callback(_clear_hit_flash)


func _clear_hit_flash() -> void:
	for index in range(_hit_flash_meshes.size()):
		var mesh_instance: MeshInstance3D = _hit_flash_meshes[index]
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _hit_flash_previous_overlays[index]


func _shake_camera_on_damage() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake"):
		camera.call("shake", damage_camera_shake_duration, damage_camera_shake_strength)


func _update_health_ui() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var health_bar := scene_root.get_node_or_null("Interface/ui04_main/MarginContainer/HBoxContainer/HealthBar") as ProgressBar
	if health_bar != null:
		health_bar.max_value = max_health
		health_bar.value = _current_health

	var health_label := scene_root.get_node_or_null("Interface/ui04_main/MarginContainer/HBoxContainer/HealthBar/HealthValueLabel") as Label
	if health_label != null:
		health_label.text = str(_current_health)


func _show_game_over_ui() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var main_ui: Node = scene_root.get_node_or_null("Interface/ui04_main")
	if main_ui != null and main_ui.has_method("show_game_over"):
		main_ui.call("show_game_over")


func _schedule_game_over_ui() -> void:
	if _game_over_was_scheduled:
		return
	_game_over_was_scheduled = true

	var delay := maxf(game_over_delay, 0.0)
	if delay <= 0.0:
		_show_game_over_ui()
		return

	get_tree().create_timer(delay).timeout.connect(_show_game_over_ui)


func _start_death() -> void:
	if _is_dead:
		return

	_is_dead = true
	_is_super_attacking = false
	_super_attack_phase = ""
	_super_attack_time_left = 0.0
	_resume_auto_shoot_after_super = false
	_stop_super_charge_effect()
	_shake_camera_on_death()
	_auto_shoot_is_enabled = false
	_resume_auto_shoot_after_dash = false
	_clear_attack_state(true)
	if _is_dashing:
		_stop_dash()
	_set_dash_hitbox_enabled(false)
	_stop_dash_dust()
	velocity = Vector3.ZERO
	_last_movement = Vector3.ZERO
	_slide_time_left = 0.0

	if animation_player == null or not animation_player.has_animation(death_animation_name):
		_schedule_game_over_ui()
		return

	if _animation_tree != null:
		_animation_tree.active = false
	animation_player.play(death_animation_name, animation_blend_time)
	_current_animation = death_animation_name


func _shake_camera_on_death() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake_camera"):
		camera.call("shake_camera")


func _start_super_attack() -> void:
	if _is_dead or _is_super_attacking:
		return

	_resume_auto_shoot_after_super = _auto_shoot_is_enabled
	_auto_shoot_is_enabled = false
	_resume_auto_shoot_after_dash = false
	_clear_attack_state(true)
	if _is_dashing:
		_stop_dash()

	_is_super_attacking = true
	_super_attack_phase = "charge"
	_super_attack_time_left = maxf(super_attack_charge_time, 0.0)
	_start_super_charge_effect()
	velocity = Vector3.ZERO
	_last_movement = Vector3.ZERO
	_slide_time_left = 0.0

	if _uses_animation_tree and _animation_tree != null and _runtime_attack_animation_names.has(super_attack_charge_animation_name):
		_play_upper_body_attack(super_attack_charge_animation_name)
	elif animation_player != null and animation_player.has_animation(super_attack_charge_animation_name):
		animation_player.play(super_attack_charge_animation_name, animation_blend_time)
		_current_animation = super_attack_charge_animation_name

	if _super_attack_time_left <= 0.0:
		_start_super_attack_shoot()


func _process_super_attack(delta: float) -> void:
	velocity = Vector3.ZERO
	if _super_attack_phase != "charge" and _super_attack_phase != "shoot":
		return

	_process_super_attack_locomotion(delta)
	_super_attack_time_left = maxf(_super_attack_time_left - delta, 0.0)
	if _super_attack_time_left <= 0.0:
		if _super_attack_phase == "charge":
			_start_super_attack_shoot()
		else:
			_finish_super_attack()


func _process_super_attack_locomotion(delta: float) -> void:
	_update_animation_tree_blends(delta)
	_update_face_direction_input(delta)
	_process_locomotion(delta)


func _start_super_attack_shoot() -> void:
	_super_attack_phase = "shoot"
	_stop_super_charge_effect()
	_spawn_super_shoot_hit_spark()
	_spawn_projectile(super_attack_projectile_scene)

	if animation_player == null or not animation_player.has_animation(super_attack_shoot_animation_name):
		_finish_super_attack()
		return

	_super_attack_time_left = _get_animation_length(super_attack_shoot_animation_name)
	if _uses_animation_tree and _animation_tree != null and _runtime_attack_animation_names.has(super_attack_shoot_animation_name):
		_play_upper_body_attack(super_attack_shoot_animation_name)
	else:
		animation_player.play(super_attack_shoot_animation_name, animation_blend_time)
		_current_animation = super_attack_shoot_animation_name
	if _super_attack_time_left <= 0.0:
		_finish_super_attack()


func _finish_super_attack() -> void:
	if not _is_super_attacking:
		return

	_is_super_attacking = false
	_super_attack_phase = ""
	_super_attack_time_left = 0.0
	_stop_super_charge_effect()
	_clear_attack_state(true)
	if _animation_tree != null:
		_animation_tree.active = true
	_current_animation = ""
	_play_animation("idle")

	_resume_auto_shoot(_resume_auto_shoot_after_super)
	_resume_auto_shoot_after_super = false


func _start_super_charge_effect() -> void:
	_stop_super_charge_effect()
	if super_attack_charge_effect_scene == null:
		return

	_active_super_charge_effect = super_attack_charge_effect_scene.instantiate() as Node3D
	if _active_super_charge_effect == null:
		return

	add_child(_active_super_charge_effect)
	_active_super_charge_effect.transform = Transform3D.IDENTITY


func _stop_super_charge_effect() -> void:
	if _active_super_charge_effect == null:
		return

	if _active_super_charge_effect.has_method("fade_out_and_free"):
		_active_super_charge_effect.call("fade_out_and_free")
	else:
		_active_super_charge_effect.queue_free()
	_active_super_charge_effect = null


func _update_attack_projectile(delta: float) -> void:
	if not _is_attacking:
		return

	if _attack_projectiles_emitted < _weapon_emit_quantity:
		_attack_projectile_emit_time_left -= delta
		while _attack_projectiles_emitted < _weapon_emit_quantity and _attack_projectile_emit_time_left <= 0.0:
			_spawn_attack_projectile()
			_attack_projectiles_emitted += 1
			if _attack_projectiles_emitted >= _weapon_emit_quantity:
				break
			if _weapon_emit_projectile_offset_time > 0.0:
				_attack_projectile_emit_time_left += _weapon_emit_projectile_offset_time

	if _attack_time_left > 0.0:
		_attack_time_left = maxf(_attack_time_left - delta, 0.0)
	if _attack_time_left <= 0.0 and _attack_projectiles_emitted >= _weapon_emit_quantity:
		_finish_attack()


func _clear_attack_state(abort_animation: bool) -> void:
	_is_attacking = false
	_attack_time_left = 0.0
	_queued_attack_animation_name = ""
	_attack_projectiles_emitted = 0
	_attack_projectile_emit_time_left = 0.0
	if _uses_animation_tree and _animation_tree != null:
		_target_attack_layer_blend_amount = 0.0
		if abort_animation:
			_attack_layer_blend_amount = 0.0
			_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)


func _finish_attack() -> void:
	if not _is_attacking:
		return
	if _attack_projectiles_emitted < _weapon_emit_quantity:
		return

	var next_attack_animation := _queued_attack_animation_name
	_queued_attack_animation_name = ""

	if next_attack_animation != "":
		_play_attack_animation(next_attack_animation)
		return

	if _auto_shoot_is_enabled:
		var selected_attack_animation := _get_next_attack_animation_name()
		if selected_attack_animation != "":
			_play_attack_animation(selected_attack_animation)
			return

	_clear_attack_state(false)
	_current_animation = ""


func _resume_auto_shoot(should_resume: bool) -> void:
	if not should_resume:
		return

	_auto_shoot_is_enabled = true
	_start_attack()


func _spawn_attack_projectile() -> void:
	_spawn_projectile(attack_projectile_scene)


func _spawn_projectile(projectile_scene: PackedScene) -> void:
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
	var spawn_transform := global_transform
	if attack_projectile_spawn != null:
		spawn_transform = attack_projectile_spawn.global_transform

	var shoot_direction := global_transform.basis.z.normalized()
	if _face_control_mode == FaceControlMode.MOUSE_CURSOR and _update_mouse_world_position_on_plane(MOUSE_AIM_PLANE_Y):
		shoot_direction = _mouse_world_position - spawn_transform.origin
		shoot_direction.y = 0.0
		if shoot_direction == Vector3.ZERO:
			shoot_direction = global_transform.basis.z.normalized()
		else:
			shoot_direction = shoot_direction.normalized()

	projectile.global_transform = Transform3D(_basis_with_y_axis(shoot_direction), spawn_transform.origin)

	if projectile.has_method("setup"):
		projectile.call("setup", shoot_direction, self)


func _basis_with_y_axis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper_axis := Vector3.UP
	if absf(y_axis.dot(helper_axis)) > 0.98:
		helper_axis = Vector3.RIGHT

	var x_axis := helper_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _get_animation_length(animation_name: String) -> float:
	if not _has_animation(animation_name):
		return 0.0

	var animation: Animation = animation_player.get_animation(animation_name)
	if animation == null:
		return 0.0

	return animation.length


func _set_dash_hitbox_enabled(is_enabled: bool) -> void:
	if dash_hitbox != null:
		dash_hitbox.set_deferred("monitoring", is_enabled)
	if dash_hitbox_shape != null:
		dash_hitbox_shape.set_deferred("disabled", not is_enabled)


func _apply_current_dash_overlaps() -> void:
	if dash_hitbox == null:
		return
	if not dash_hitbox.monitoring:
		return
	if _is_dash_bouncing_back:
		return

	for body in dash_hitbox.get_overlapping_bodies():
		_apply_dash_hit(body)
	for area in dash_hitbox.get_overlapping_areas():
		_apply_dash_hit(area)


func _on_dash_hitbox_body_entered(body: Node3D) -> void:
	_apply_dash_hit(body)


func _on_dash_hitbox_area_entered(area: Area3D) -> void:
	_apply_dash_hit(area)


func _apply_dash_hit(target: Node) -> void:
	if not _is_dashing:
		return
	if target == self or is_ancestor_of(target) or target.is_ancestor_of(self):
		return
	if _dash_hit_targets.has(target):
		return

	_dash_hit_targets.append(target)
	var hit_was_applied := false
	if target.has_method("take_dash_hit"):
		target.call("take_dash_hit", _dash_direction, _weapon_dash_damage)
		hit_was_applied = true
	elif target.has_method("take_damage"):
		target.call("take_damage", _weapon_dash_damage)
		hit_was_applied = true

	if not hit_was_applied:
		return

	_spawn_dash_hit_spark(target)
	_shake_camera_on_dash_hit()
	_start_dash_bounce_back()


func _start_dash_bounce_back() -> void:
	if _is_dash_bouncing_back:
		return

	_is_dash_bouncing_back = true
	_dash_bounce_elapsed = 0.0
	_dash_bounce_distance_ratio = 0.0
	_dash_time_left = 0.0
	_set_dash_hitbox_enabled(false)


func _shake_camera_on_dash_hit() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake"):
		camera.call("shake", dash_hit_camera_shake_duration, dash_hit_camera_shake_strength)


func _spawn_dash_hit_spark(target: Node) -> void:
	if not target is Node3D:
		return

	_spawn_hit_spark_at_position(
		dash_hit_spark_scene,
		(target as Node3D).global_position + Vector3.UP * dash_hit_spark_height
	)


func _spawn_super_shoot_hit_spark() -> void:
	if attack_projectile_spawn == null:
		return

	_spawn_hit_spark_at_position(
		super_attack_shoot_hit_spark_scene,
		attack_projectile_spawn.global_position
	)


func _spawn_hit_spark_at_position(spark_scene: PackedScene, spawn_position: Vector3) -> void:
	if spark_scene == null:
		return

	var hit_spark := spark_scene.instantiate() as Node3D
	if hit_spark == null:
		return

	var spark_parent := get_tree().current_scene
	if spark_parent == null:
		spark_parent = self

	spark_parent.add_child(hit_spark)
	hit_spark.global_position = spawn_position

	var longest_lifetime := _restart_particles_recursive(hit_spark)
	hit_spark.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(hit_spark.queue_free)


func _start_dash_dust() -> void:
	if _active_dash_dust != null:
		_release_dash_dust(_active_dash_dust)

	var dust := _create_dash_dust()
	if dust == null:
		return

	add_child(dust)
	if dash_dust_template != null:
		dust.transform = dash_dust_template.transform
	else:
		dust.position = Vector3.ZERO

	_active_dash_dust = dust
	_start_particles_recursive(dust)


func _stop_dash_dust() -> void:
	if _active_dash_dust != null:
		_release_dash_dust(_active_dash_dust)
		_active_dash_dust = null

	if dash_dust_template != null:
		_stop_particles_recursive(dash_dust_template)


func _create_dash_dust() -> Node3D:
	if dash_dust_scene != null:
		return dash_dust_scene.instantiate() as Node3D
	if dash_dust_template != null:
		return dash_dust_template.duplicate() as Node3D

	return null


func _release_dash_dust(dust: Node3D) -> void:
	if dust == null or not is_instance_valid(dust):
		return

	var dust_parent := get_tree().current_scene
	if dust_parent == null:
		dust_parent = get_parent()

	if dust_parent != null and dust.get_parent() != dust_parent:
		var dust_transform := dust.global_transform
		dust.get_parent().remove_child(dust)
		dust_parent.add_child(dust)
		dust.global_transform = dust_transform

	var longest_lifetime := _stop_particles_recursive(dust)
	dust.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(dust.queue_free)


func _start_particles_recursive(node: Node) -> float:
	var longest_lifetime := 1.0

	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.one_shot = false
		particles.restart()
		particles.emitting = true
		longest_lifetime = maxf(longest_lifetime, particles.lifetime)

	for child in node.get_children():
		longest_lifetime = maxf(longest_lifetime, _start_particles_recursive(child))

	return longest_lifetime


func _restart_particles_recursive(node: Node) -> float:
	var longest_lifetime := 1.0

	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.one_shot = true
		particles.restart()
		particles.emitting = true
		longest_lifetime = maxf(longest_lifetime, particles.lifetime)

	for child in node.get_children():
		longest_lifetime = maxf(longest_lifetime, _restart_particles_recursive(child))

	return longest_lifetime


func _stop_particles_recursive(node: Node) -> float:
	var longest_lifetime := 1.0

	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		longest_lifetime = maxf(longest_lifetime, particles.lifetime)

	for child in node.get_children():
		longest_lifetime = maxf(longest_lifetime, _stop_particles_recursive(child))

	return longest_lifetime


func _face_direction(direction: Vector3, delta: float, face_turn_speed: float = -1.0) -> void:
	if direction == Vector3.ZERO:
		return

	var current_direction := global_transform.basis.z
	current_direction.y = 0.0
	if current_direction == Vector3.ZERO:
		current_direction = Vector3.FORWARD
	else:
		current_direction = current_direction.normalized()

	var target_direction := direction
	target_direction.y = 0.0
	target_direction = target_direction.normalized()

	var current_yaw := atan2(current_direction.x, current_direction.z)
	var target_yaw := atan2(target_direction.x, target_direction.z)
	var rotation_speed := mouse_turn_speed
	if face_turn_speed >= 0.0:
		rotation_speed = face_turn_speed

	var next_yaw := rotate_toward(current_yaw, target_yaw, rotation_speed * delta)
	var next_direction := Vector3(sin(next_yaw), 0.0, cos(next_yaw)).normalized()
	global_transform = global_transform.looking_at(global_position - next_direction, Vector3.UP)


func _update_face_direction_input(delta: float) -> void:
	var toggle_is_pressed := Input.is_physical_key_pressed(KEY_Q)
	if toggle_is_pressed and not _face_control_toggle_was_pressed:
		if _face_control_mode == FaceControlMode.KEY_ARROW:
			_face_control_mode = FaceControlMode.MOUSE_CURSOR
		else:
			_face_control_mode = FaceControlMode.KEY_ARROW

	_face_control_toggle_was_pressed = toggle_is_pressed

	if _face_control_mode == FaceControlMode.MOUSE_CURSOR:
		_face_mouse_cursor(delta)
	else:
		_face_keyboard_arrow(delta)


func _face_keyboard_arrow(delta: float) -> void:
	var face_direction := _update_keyboard_face_target_direction(delta)
	if face_direction != Vector3.ZERO:
		_last_keyboard_face_direction = face_direction
		_has_keyboard_face_target = true

	if _has_keyboard_face_target:
		_face_direction(_last_keyboard_face_direction, delta, arrow_face_turn_speed)


func _update_keyboard_face_target_direction(delta: float) -> Vector3:
	var up_is_pressed := Input.is_physical_key_pressed(KEY_UP)
	var down_is_pressed := Input.is_physical_key_pressed(KEY_DOWN)
	var left_is_pressed := Input.is_physical_key_pressed(KEY_LEFT)
	var right_is_pressed := Input.is_physical_key_pressed(KEY_RIGHT)
	var face_direction := Vector3.ZERO
	var pressed_direction_count := 0
	var combined_direction := Vector3.ZERO

	if up_is_pressed:
		pressed_direction_count += 1
		combined_direction += Vector3.FORWARD
	if down_is_pressed:
		pressed_direction_count += 1
		combined_direction += Vector3.BACK
	if left_is_pressed:
		pressed_direction_count += 1
		combined_direction += Vector3.LEFT
	if right_is_pressed:
		pressed_direction_count += 1
		combined_direction += Vector3.RIGHT

	if pressed_direction_count >= 2 and combined_direction != Vector3.ZERO:
		face_direction = combined_direction.normalized()
	elif up_is_pressed and not _keyboard_face_up_was_pressed:
		face_direction = _step_keyboard_face_target_toward(Vector3.FORWARD)
	elif down_is_pressed and not _keyboard_face_down_was_pressed:
		face_direction = _step_keyboard_face_target_toward(Vector3.BACK)
	elif left_is_pressed and not _keyboard_face_left_was_pressed:
		face_direction = _step_keyboard_face_target_toward(Vector3.LEFT)
	elif right_is_pressed and not _keyboard_face_right_was_pressed:
		face_direction = _step_keyboard_face_target_toward(Vector3.RIGHT)
	elif up_is_pressed:
		face_direction = _move_keyboard_face_target_toward(Vector3.FORWARD, delta)
	elif down_is_pressed:
		face_direction = _move_keyboard_face_target_toward(Vector3.BACK, delta)
	elif left_is_pressed:
		face_direction = _move_keyboard_face_target_toward(Vector3.LEFT, delta)
	elif right_is_pressed:
		face_direction = _move_keyboard_face_target_toward(Vector3.RIGHT, delta)

	_keyboard_face_up_was_pressed = up_is_pressed
	_keyboard_face_down_was_pressed = down_is_pressed
	_keyboard_face_left_was_pressed = left_is_pressed
	_keyboard_face_right_was_pressed = right_is_pressed

	return face_direction


func _step_keyboard_face_target_toward(target_direction: Vector3) -> Vector3:
	var step_radians := deg_to_rad(maxf(arrow_face_turn_step_degrees, 0.0))
	return _rotate_keyboard_face_target_toward(target_direction, step_radians)


func _move_keyboard_face_target_toward(target_direction: Vector3, delta: float) -> Vector3:
	var step_radians := maxf(arrow_face_turn_speed, 0.0) * delta
	return _rotate_keyboard_face_target_toward(target_direction, step_radians)


func _rotate_keyboard_face_target_toward(target_direction: Vector3, step_radians: float) -> Vector3:
	var current_direction := _last_keyboard_face_direction
	if not _has_keyboard_face_target:
		current_direction = global_transform.basis.z
		current_direction.y = 0.0
		if current_direction == Vector3.ZERO:
			current_direction = Vector3.FORWARD
		else:
			current_direction = current_direction.normalized()

	var current_yaw := atan2(current_direction.x, current_direction.z)
	var target_yaw := atan2(target_direction.x, target_direction.z)
	var next_yaw := rotate_toward(current_yaw, target_yaw, step_radians)
	return Vector3(sin(next_yaw), 0.0, cos(next_yaw)).normalized()


func _face_mouse_cursor(delta: float) -> void:
	if not _update_mouse_world_position_on_plane(MOUSE_AIM_PLANE_Y):
		return

	var face_direction := _mouse_world_position - global_position
	face_direction.y = 0.0
	_face_direction(face_direction.normalized(), delta, mouse_turn_speed)


func is_mouse_face_control_enabled() -> bool:
	return _face_control_mode == FaceControlMode.MOUSE_CURSOR


func _update_mouse_world_position_on_plane(plane_y: float) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) <= 0.001:
		return false

	var distance_to_plane := (plane_y - ray_origin.y) / ray_direction.y
	if distance_to_plane <= 0.0:
		return false

	_mouse_world_position = ray_origin + ray_direction * distance_to_plane
	return true


func _on_animation_finished(animation_name: StringName) -> void:
	if _is_dead and String(animation_name) == death_animation_name:
		_schedule_game_over_ui()
		return
	if _is_super_attacking and _super_attack_phase == "shoot" and String(animation_name) == super_attack_shoot_animation_name:
		_finish_super_attack()
		return
	if _is_attack_animation(String(animation_name)):
		_finish_attack()
	if _is_dash_animation(String(animation_name)):
		_current_animation = ""


func _setup_animation_tree() -> void:
	if animation_player == null or skeleton == null:
		return
	if not _has_animation("idle") or not _has_animation("walk") or _get_valid_dash_animation_names().is_empty() or not _has_animation(attack_idle_animation_name) or _get_valid_attack_animation_names().is_empty():
		return

	var animation_root := animation_player.get_parent()
	if animation_root == null:
		return
	if not _setup_split_body_runtime_animations():
		return

	_animation_tree = animation_root.get_node_or_null("HeroAnimationTree") as AnimationTree
	if _animation_tree == null:
		_animation_tree = AnimationTree.new()
		_animation_tree.name = "HeroAnimationTree"
		animation_root.add_child(_animation_tree)

	var tree_root := AnimationNodeBlendTree.new()
	_animation_tree.tree_root = tree_root
	_animation_tree.anim_player = animation_player.get_path()

	_add_animation_tree_animation(tree_root, "Idle", _runtime_idle_animation_name)
	_add_animation_tree_animation(tree_root, "Walk", _runtime_walk_animation_name)
	_dash_animation_node = _add_animation_tree_animation(tree_root, "Dash", _runtime_dash_animation_name)
	_add_animation_tree_animation(tree_root, "AttackIdle", _runtime_attack_idle_animation_name)
	var first_attack_animation := _get_runtime_attack_animation_name(_get_valid_attack_animation_names()[0])
	_attack_animation_node_a = _add_animation_tree_animation(tree_root, "AttackA", first_attack_animation)
	_attack_animation_node_b = _add_animation_tree_animation(tree_root, "AttackB", first_attack_animation)

	var locomotion_blend := AnimationNodeBlend2.new()
	locomotion_blend.filter_enabled = true
	tree_root.add_node("LocomotionBlend", locomotion_blend, Vector2(280.0, 0.0))
	tree_root.connect_node("LocomotionBlend", 0, "Idle")
	tree_root.connect_node("LocomotionBlend", 1, "Walk")

	var dash_blend := AnimationNodeBlend2.new()
	dash_blend.filter_enabled = false
	tree_root.add_node("DashBlend", dash_blend, Vector2(560.0, 0.0))
	tree_root.connect_node("DashBlend", 0, "LocomotionBlend")

	tree_root.add_node("DashSeek", AnimationNodeTimeSeek.new(), Vector2(560.0, 160.0))
	tree_root.connect_node("DashSeek", 0, "Dash")
	tree_root.connect_node("DashBlend", 1, "DashSeek")

	var upper_idle_blend := AnimationNodeBlend2.new()
	upper_idle_blend.filter_enabled = true
	tree_root.add_node("UpperIdleBlend", upper_idle_blend, Vector2(840.0, -120.0))
	tree_root.connect_node("UpperIdleBlend", 0, "DashBlend")
	tree_root.connect_node("UpperIdleBlend", 1, "AttackIdle")

	var attack_blend := AnimationNodeBlend2.new()
	attack_blend.filter_enabled = true
	tree_root.add_node("AttackBlend", attack_blend, Vector2(1120.0, 120.0))
	tree_root.connect_node("AttackBlend", 0, "AttackA")
	tree_root.connect_node("AttackBlend", 1, "AttackB")

	var attack_layer_blend := AnimationNodeBlend2.new()
	attack_layer_blend.filter_enabled = true
	tree_root.add_node("AttackLayerBlend", attack_layer_blend, Vector2(1400.0, 0.0))
	tree_root.connect_node("AttackLayerBlend", 0, "UpperIdleBlend")
	tree_root.connect_node("AttackLayerBlend", 1, "AttackBlend")
	tree_root.connect_node("output", 0, "AttackLayerBlend")

	_apply_lower_body_locomotion_filter(locomotion_blend, animation_root)
	_apply_upper_body_filter(upper_idle_blend, animation_root)
	_apply_upper_body_filter(attack_blend, animation_root)
	_apply_upper_body_filter(attack_layer_blend, animation_root)
	_animation_tree.active = true
	_uses_animation_tree = true
	_animation_tree.set("parameters/UpperIdleBlend/blend_amount", _upper_idle_blend_amount)
	_animation_tree.set("parameters/LocomotionBlend/blend_amount", _locomotion_blend_amount)
	_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	_animation_tree.set("parameters/AttackBlend/blend_amount", _attack_blend_amount)
	_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)
	_set_locomotion_animation("idle")


func _add_animation_tree_animation(tree_root: AnimationNodeBlendTree, node_name: String, animation_name: String) -> AnimationNodeAnimation:
	var animation_node := AnimationNodeAnimation.new()
	animation_node.animation = StringName(animation_name)
	tree_root.add_node(node_name, animation_node)
	return animation_node


func _setup_split_body_runtime_animations() -> bool:
	var lower_bone_index := skeleton.find_bone(attack_lower_body_bone_name)
	var upper_bone_index := skeleton.find_bone(attack_upper_body_bone_name)
	if lower_bone_index == -1 or upper_bone_index == -1:
		return false

	var lower_bones := _get_bone_index_lookup(_get_bone_and_children_indices(lower_bone_index))
	var upper_bones := _get_bone_index_lookup(_get_bone_and_children_indices(upper_bone_index))
	for bone_index in upper_bones.keys():
		lower_bones.erase(bone_index)

	var runtime_library := AnimationLibrary.new()
	_runtime_idle_animation_name = "hero_split/idle_lower"
	_runtime_walk_animation_name = "hero_split/walk_lower"
	_runtime_dash_animation_name = _get_valid_dash_animation_names()[0]
	_runtime_attack_idle_animation_name = "hero_split/" + attack_idle_animation_name + "_upper"
	_runtime_attack_animation_names.clear()

	runtime_library.add_animation("idle_lower", _create_body_filtered_animation("idle", lower_bones))
	runtime_library.add_animation("walk_lower", _create_body_filtered_animation("walk", lower_bones))
	runtime_library.add_animation(attack_idle_animation_name + "_upper", _create_body_filtered_animation(attack_idle_animation_name, upper_bones))

	for attack_name in _get_valid_attack_animation_names():
		var runtime_name := attack_name + "_upper"
		runtime_library.add_animation(runtime_name, _create_body_filtered_animation(attack_name, upper_bones))
		_runtime_attack_animation_names[attack_name] = "hero_split/" + runtime_name

	if _has_animation(super_attack_charge_animation_name):
		var super_charge_runtime_name := super_attack_charge_animation_name + "_upper"
		runtime_library.add_animation(super_charge_runtime_name, _create_body_filtered_animation(super_attack_charge_animation_name, upper_bones))
		_runtime_attack_animation_names[super_attack_charge_animation_name] = "hero_split/" + super_charge_runtime_name

	if _has_animation(super_attack_shoot_animation_name):
		var super_shoot_runtime_name := super_attack_shoot_animation_name + "_upper"
		runtime_library.add_animation(super_shoot_runtime_name, _create_body_filtered_animation(super_attack_shoot_animation_name, upper_bones))
		_runtime_attack_animation_names[super_attack_shoot_animation_name] = "hero_split/" + super_shoot_runtime_name

	if animation_player.has_animation_library("hero_split"):
		animation_player.remove_animation_library("hero_split")
	animation_player.add_animation_library("hero_split", runtime_library)
	return true


func _create_body_filtered_animation(animation_name: String, allowed_bones: Dictionary) -> Animation:
	var source_animation := animation_player.get_animation(animation_name)
	var filtered_animation := source_animation.duplicate(true) as Animation

	for track_index in range(filtered_animation.get_track_count() - 1, -1, -1):
		var bone_index := _get_skeleton_bone_index_from_track_path(filtered_animation.track_get_path(track_index))
		if bone_index != -1 and not allowed_bones.has(bone_index):
			filtered_animation.remove_track(track_index)

	return filtered_animation


func _get_skeleton_bone_index_from_track_path(track_path: NodePath) -> int:
	var track_path_text := String(track_path)
	var separator_index := track_path_text.rfind(":")
	if separator_index == -1:
		return -1

	var bone_name := track_path_text.substr(separator_index + 1)
	return skeleton.find_bone(bone_name)


func _get_bone_index_lookup(bone_indices: Array[int]) -> Dictionary:
	var lookup := {}
	for bone_index in bone_indices:
		lookup[bone_index] = true
	return lookup


func _get_runtime_attack_animation_name(animation_name: String) -> String:
	return _runtime_attack_animation_names.get(animation_name, animation_name)


func _apply_lower_body_locomotion_filter(locomotion_node: AnimationNode, animation_root: Node) -> void:
	var lower_bone_index := skeleton.find_bone(attack_lower_body_bone_name)
	if lower_bone_index == -1:
		push_warning("Attack lower body bone not found: " + attack_lower_body_bone_name)
		return

	var excluded_upper_bones := {}
	var upper_bone_index := skeleton.find_bone(attack_upper_body_bone_name)
	if upper_bone_index != -1:
		for bone_index in _get_bone_and_children_indices(upper_bone_index):
			excluded_upper_bones[bone_index] = true
	else:
		push_warning("Attack upper body bone not found: " + attack_upper_body_bone_name)

	var skeleton_path := String(animation_root.get_path_to(skeleton))
	for bone_index in _get_bone_and_children_indices(lower_bone_index):
		if excluded_upper_bones.has(bone_index):
			continue

		var bone_path := NodePath(skeleton_path + ":" + skeleton.get_bone_name(bone_index))
		locomotion_node.set_filter_path(bone_path, true)


func _apply_upper_body_filter(animation_node: AnimationNode, animation_root: Node) -> void:
	var upper_bone_index := skeleton.find_bone(attack_upper_body_bone_name)
	if upper_bone_index == -1:
		push_warning("Attack upper body bone not found: " + attack_upper_body_bone_name)
		return
	if attack_lower_body_bone_name != "" and skeleton.find_bone(attack_lower_body_bone_name) == -1:
		push_warning("Attack lower body bone not found: " + attack_lower_body_bone_name)

	var skeleton_path := String(animation_root.get_path_to(skeleton))
	for bone_path in _get_bone_and_children_filter_paths(upper_bone_index, skeleton_path):
		animation_node.set_filter_path(bone_path, true)


func _get_bone_and_children_filter_paths(bone_index: int, skeleton_path: String) -> Array[NodePath]:
	var result: Array[NodePath] = []
	_collect_bone_and_children_filter_paths(bone_index, skeleton_path, result)
	return result


func _get_bone_and_children_indices(bone_index: int) -> Array[int]:
	var result: Array[int] = []
	_collect_bone_and_children_indices(bone_index, result)
	return result


func _collect_bone_and_children_filter_paths(bone_index: int, skeleton_path: String, result: Array[NodePath]) -> void:
	result.append(NodePath(skeleton_path + ":" + skeleton.get_bone_name(bone_index)))

	for child_index in skeleton.get_bone_children(bone_index):
		_collect_bone_and_children_filter_paths(child_index, skeleton_path, result)


func _collect_bone_and_children_indices(bone_index: int, result: Array[int]) -> void:
	result.append(bone_index)

	for child_index in skeleton.get_bone_children(bone_index):
		_collect_bone_and_children_indices(child_index, result)


func _get_next_attack_animation_name() -> String:
	var attack_names := _get_valid_attack_animation_names()
	if attack_names.is_empty():
		return ""

	if _next_attack_animation_index >= attack_names.size():
		_next_attack_animation_index = 0

	var animation_name := attack_names[_next_attack_animation_index]
	_next_attack_animation_index = (_next_attack_animation_index + 1) % attack_names.size()
	return animation_name


func _get_valid_attack_animation_names() -> PackedStringArray:
	return _get_valid_animation_names(attack_animation_cycle, attack_animation_name)


func _get_next_dash_animation_name() -> String:
	var dash_names := _get_valid_dash_animation_names()
	if dash_names.is_empty():
		return ""

	if _next_dash_animation_index >= dash_names.size():
		_next_dash_animation_index = 0

	var animation_name := dash_names[_next_dash_animation_index]
	_next_dash_animation_index = (_next_dash_animation_index + 1) % dash_names.size()
	return animation_name


func _get_valid_dash_animation_names() -> PackedStringArray:
	return _get_valid_animation_names(dash_animation_cycle, dash_animation_name)


func _get_valid_animation_names(animation_cycle: PackedStringArray, fallback_animation_name: String) -> PackedStringArray:
	var valid_names := PackedStringArray()
	for animation_name in animation_cycle:
		if animation_name != "" and _has_animation(animation_name):
			valid_names.append(animation_name)

	if valid_names.is_empty() and fallback_animation_name != "" and _has_animation(fallback_animation_name):
		valid_names.append(fallback_animation_name)

	return valid_names


func _is_attack_animation(animation_name: String) -> bool:
	return animation_name == attack_animation_name or attack_animation_cycle.has(animation_name)


func _is_dash_animation(animation_name: String) -> bool:
	return animation_name == dash_animation_name or dash_animation_cycle.has(animation_name)


func _play_animation(animation_name: String, force_restart := false) -> void:
	if not _has_animation(animation_name):
		return
	if _uses_animation_tree:
		if _is_attack_animation(animation_name):
			_play_upper_body_attack(animation_name)
			return
		if _is_dash_animation(animation_name):
			_play_dash_animation(animation_name)
			return
		_set_locomotion_animation(animation_name)
		return
	if _current_animation == animation_name and not force_restart:
		return

	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name


func _play_upper_body_attack(animation_name: String) -> void:
	if _animation_tree == null:
		return

	var runtime_animation_name := StringName(_get_runtime_attack_animation_name(animation_name))
	if _active_attack_blend_slot == 0:
		if _attack_animation_node_b != null:
			_attack_animation_node_b.animation = runtime_animation_name
		_active_attack_blend_slot = 1
		_target_attack_blend_amount = 1.0
	else:
		if _attack_animation_node_a != null:
			_attack_animation_node_a.animation = runtime_animation_name
		_active_attack_blend_slot = 0
		_target_attack_blend_amount = 0.0

	_target_attack_layer_blend_amount = 1.0
	_current_animation = animation_name


func _play_dash_animation(animation_name: String) -> void:
	if _animation_tree == null:
		return

	if _dash_animation_node != null:
		_dash_animation_node.animation = StringName(animation_name)

	_set_locomotion_animation(animation_name)
	_animation_tree.set("parameters/DashSeek/seek_request", 0.0)


func _set_locomotion_animation(animation_name: String) -> void:
	if _animation_tree == null:
		return
	if _current_animation == animation_name:
		return

	if animation_name == "walk":
		_target_locomotion_blend_amount = 1.0
		_target_dash_blend_amount = 0.0
		_target_upper_idle_blend_amount = 1.0
	elif _is_dash_animation(animation_name):
		_target_dash_blend_amount = 1.0
		_dash_blend_amount = 1.0
		_target_upper_idle_blend_amount = 0.0
		_target_attack_layer_blend_amount = 0.0
		_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	elif animation_name == "idle":
		_target_locomotion_blend_amount = 0.0
		_target_dash_blend_amount = 0.0
		_target_upper_idle_blend_amount = 1.0
	else:
		return

	_current_animation = animation_name


func _update_animation_tree_blends(delta: float) -> void:
	if not _uses_animation_tree or _animation_tree == null:
		return

	var blend_step := 1.0
	if animation_blend_time > 0.0:
		blend_step = clampf(delta / animation_blend_time, 0.0, 1.0)

	_locomotion_blend_amount = move_toward(_locomotion_blend_amount, _target_locomotion_blend_amount, blend_step)
	_dash_blend_amount = move_toward(_dash_blend_amount, _target_dash_blend_amount, blend_step)
	_upper_idle_blend_amount = move_toward(_upper_idle_blend_amount, _target_upper_idle_blend_amount, blend_step)
	_attack_blend_amount = move_toward(_attack_blend_amount, _target_attack_blend_amount, blend_step)
	_attack_layer_blend_amount = move_toward(_attack_layer_blend_amount, _target_attack_layer_blend_amount, blend_step)
	_animation_tree.set("parameters/LocomotionBlend/blend_amount", _locomotion_blend_amount)
	_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	_animation_tree.set("parameters/UpperIdleBlend/blend_amount", _upper_idle_blend_amount)
	_animation_tree.set("parameters/AttackBlend/blend_amount", _attack_blend_amount)
	_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)


func _has_animation(animation_name: String) -> bool:
	return animation_player != null and animation_player.has_animation(animation_name)
