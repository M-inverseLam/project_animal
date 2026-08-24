extends CharacterBody3D

@export var move_speed: float = 4.0
@export var face_turn_speed: float = 4.0
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
@export var weapon_socket_path: NodePath = NodePath("shootposition")

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
@export var weapon_emitter_scene: PackedScene
@export var dash_animation_name: String = "dash"
@export var dash_animation_cycle: PackedStringArray = PackedStringArray(["dash", "dash02"])
@export var dash_cooldown: float = 0.5
@export var dash_dust_scene: PackedScene

@export_group("")

@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
@onready var visual_root := get_node_or_null("hero_girl01") as Node3D
@onready var dash_dust_template := get_node_or_null("DashDust") as Node3D
@onready var weapon_socket := get_node_or_null(weapon_socket_path) as Node3D
@onready var gem_attraction_shape := get_node_or_null("GemAttractionArea/CollisionShape3D") as CollisionShape3D

var _current_animation := ""
var _animation_tree: AnimationTree
var _attack_animation_node_a: AnimationNodeAnimation
var _attack_animation_node_b: AnimationNodeAnimation
var _dash_animation_node: AnimationNodeAnimation
var _uses_animation_tree := false
var _runtime_dash_animation_name := ""
var _locomotion_blend_amount := 0.0
var _target_locomotion_blend_amount := 0.0
var _dash_blend_amount := 0.0
var _target_dash_blend_amount := 0.0
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
var _is_attacking := false
var _attack_time_left := 0.0
var _combo_attack_is_queued := false
var _combo_continue_time_left := 0.0
var _active_combo: HeroComboAttack
var _combo_move_direction := Vector3.FORWARD
var _combo_distance_traveled := 0.0
var _combo_move_elapsed := 0.0
var _combo_move_distance_ratio := 0.0
var _melee_hit_stop_time_left := 0.0
var _animation_tree_was_active_before_hit_stop := false
var _animation_player_was_playing_before_hit_stop := false
var _is_super_attacking := false
var _super_attack_phase := ""
var _super_attack_time_left := 0.0
var _active_super_charge_effect: Node3D
var _dash_key_was_pressed := false
var _is_dashing := false
var _next_dash_animation_index := 0
var _dash_time_left := 0.0
var _dash_elapsed := 0.0
var _dash_distance_ratio := 0.0
var _dash_direction := Vector3.ZERO
var _dash_cooldown_time_left := 0.0
var _active_dash_dust: Node3D
var _weapon_dash_time := 0.5
var _weapon_dash_speed := 10.0
var _weapon_dash_speed_curve: Curve
var _active_weapon_emitter: MeleeComboEmitter


func _ready() -> void:
	_current_health = max_health
	_update_health_ui()
	_update_gem_attraction_radius()
	_cache_hit_flash_meshes()
	equip_weapon(weapon_emitter_scene)
	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	_setup_animation_tree()
	_stop_dash_dust()
	_play_animation("idle")


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
	if _process_melee_hit_stop(delta):
		return
	if _is_super_attacking:
		_process_super_attack(delta)
		return

	_update_dash_cooldown(delta)
	_update_animation_tree_blends(delta)
	_update_combo_continue_window(delta)
	_update_attack_input()
	_update_attack_animation(delta)
	if _is_attacking:
		_process_combo_movement(delta)
		return

	_face_keyboard_movement(delta)

	_update_dash_input()

	if _is_dashing:
		_process_dash(delta)
		return

	_process_locomotion(delta)


func start_melee_hit_stop(duration: float) -> void:
	duration = maxf(duration, 0.0)
	if duration <= 0.0 or not _is_attacking or _is_dead:
		return

	var hit_stop_was_active := _melee_hit_stop_time_left > 0.0
	_melee_hit_stop_time_left = maxf(_melee_hit_stop_time_left, duration)
	if hit_stop_was_active:
		return

	if _animation_tree != null:
		_animation_tree_was_active_before_hit_stop = _animation_tree.active
		if _animation_tree_was_active_before_hit_stop:
			_animation_tree.set("parameters/AttackTimeScale/scale", 0.0)
	elif animation_player != null and animation_player.is_playing():
		_animation_player_was_playing_before_hit_stop = true
		animation_player.pause()


func _process_melee_hit_stop(delta: float) -> bool:
	if _melee_hit_stop_time_left <= 0.0:
		return false

	velocity = Vector3.ZERO
	_melee_hit_stop_time_left = maxf(_melee_hit_stop_time_left - maxf(delta, 0.0), 0.0)
	if _melee_hit_stop_time_left <= 0.0:
		_finish_melee_hit_stop()
	return true


func _finish_melee_hit_stop() -> void:
	_melee_hit_stop_time_left = 0.0
	if not _is_dead and _animation_tree != null and _animation_tree_was_active_before_hit_stop:
		_animation_tree.set("parameters/AttackTimeScale/scale", 1.0)
	if not _is_dead and animation_player != null and _animation_player_was_playing_before_hit_stop:
		animation_player.play()
	_animation_tree_was_active_before_hit_stop = false
	_animation_player_was_playing_before_hit_stop = false


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
	var attack_key_is_pressed := Input.is_physical_key_pressed(KEY_LEFT)

	if attack_key_is_pressed and not _attack_key_was_pressed:
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
	if _is_attacking:
		_combo_attack_is_queued = true
		return

	var combo := _get_next_combo_attack()
	if combo == null or combo.animation_name.is_empty() or not _has_animation(String(combo.animation_name)):
		return

	_play_combo_attack(combo)


func _play_combo_attack(combo: HeroComboAttack) -> void:
	_active_combo = combo
	_is_attacking = true
	_combo_attack_is_queued = false
	_combo_continue_time_left = 0.0
	_combo_distance_traveled = 0.0
	_combo_move_elapsed = 0.0
	_combo_move_distance_ratio = 0.0
	_combo_move_direction = global_transform.basis.z.normalized()
	_attack_time_left = _get_animation_length(String(combo.animation_name))

	_spawn_combo_weapon(combo)
	_play_animation(String(combo.animation_name), true)


func _process_combo_movement(delta: float) -> void:
	if _active_combo == null:
		return

	var combo_move_speed := maxf(_active_combo.move_speed, 0.0)
	var combo_move_time := maxf(_active_combo.move_time, 0.0)
	if combo_move_time <= 0.0 or combo_move_speed <= 0.0:
		velocity = Vector3.ZERO
		return

	var total_move_distance := combo_move_speed * combo_move_time
	_combo_move_elapsed = minf(_combo_move_elapsed + maxf(delta, 0.0), combo_move_time)
	var progress := _combo_move_elapsed / combo_move_time
	var distance_ratio := _sample_movement_speed_curve(_active_combo.movement_speed_curve, progress)
	distance_ratio = maxf(distance_ratio, _combo_move_distance_ratio)
	var frame_distance := maxf(distance_ratio - _combo_move_distance_ratio, 0.0) * total_move_distance
	_combo_move_distance_ratio = distance_ratio
	if frame_distance <= 0.0:
		velocity = Vector3.ZERO
		return

	var start_position := global_position
	_move_with_collision(_combo_move_direction * frame_distance, delta)
	var moved_offset := global_position - start_position
	moved_offset.y = 0.0
	_combo_distance_traveled += moved_offset.length()


func _sample_movement_speed_curve(speed_curve: Curve, progress: float) -> float:
	progress = clampf(progress, 0.0, 1.0)
	if speed_curve == null:
		return progress

	const INTEGRATION_STEPS := 32
	var total_area := 0.0
	var traveled_area := 0.0
	var previous_time := 0.0
	var previous_speed := maxf(speed_curve.sample_baked(0.0), 0.0)
	for step in range(1, INTEGRATION_STEPS + 1):
		var current_time := float(step) / float(INTEGRATION_STEPS)
		var current_speed := maxf(speed_curve.sample_baked(current_time), 0.0)
		var step_area := (previous_speed + current_speed) * 0.5 * (current_time - previous_time)
		total_area += step_area

		if progress >= current_time:
			traveled_area += step_area
		elif progress > previous_time:
			var step_progress := (progress - previous_time) / (current_time - previous_time)
			var speed_at_progress := lerpf(previous_speed, current_speed, step_progress)
			traveled_area += (previous_speed + speed_at_progress) * 0.5 * (progress - previous_time)

		previous_time = current_time
		previous_speed = current_speed

	if total_area <= 0.000001:
		return 0.0
	return clampf(traveled_area / total_area, 0.0, 1.0)


func _spawn_combo_weapon(combo: HeroComboAttack) -> void:
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	if combo_emitter != null:
		combo_emitter.spawn_combo_weapon(combo, self, _combo_move_direction)


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

	_clear_attack_state(true)
	_is_dashing = true
	_dash_time_left = _weapon_dash_time
	_dash_elapsed = 0.0
	_dash_distance_ratio = 0.0
	_dash_direction = _get_dash_direction()
	_last_movement = _dash_direction
	_slide_time_left = 0.0

	_start_dash_dust()
	_play_animation(selected_dash_animation, true)


func _process_dash(delta: float) -> void:
	if _weapon_dash_time <= 0.0:
		_stop_dash()
		return

	_dash_elapsed = minf(_dash_elapsed + maxf(delta, 0.0), _weapon_dash_time)
	var progress := _dash_elapsed / _weapon_dash_time
	var distance_ratio := _sample_movement_speed_curve(_weapon_dash_speed_curve, progress)
	distance_ratio = maxf(distance_ratio, _dash_distance_ratio)
	var total_dash_distance := _weapon_dash_speed * _weapon_dash_time
	var frame_distance := maxf(distance_ratio - _dash_distance_ratio, 0.0) * total_dash_distance

	_move_with_collision(_dash_direction * frame_distance, delta)
	_dash_distance_ratio = distance_ratio
	_dash_time_left = maxf(_weapon_dash_time - _dash_elapsed, 0.0)

	if _dash_time_left <= 0.0:
		_stop_dash()


func _stop_dash() -> void:
	_is_dashing = false
	_dash_time_left = 0.0
	_dash_elapsed = 0.0
	_dash_distance_ratio = 0.0
	_stop_dash_dust()
	_dash_cooldown_time_left = dash_cooldown
	_current_animation = ""


func _get_dash_direction() -> Vector3:
	var input_direction := _get_keyboard_movement()
	if input_direction != Vector3.ZERO:
		return input_direction

	return global_transform.basis.z.normalized()


func equip_weapon(emitter_scene: PackedScene) -> void:
	if _active_weapon_emitter != null:
		_active_weapon_emitter.queue_free()
		_active_weapon_emitter = null

	weapon_emitter_scene = emitter_scene
	if weapon_emitter_scene == null or weapon_socket == null:
		return

	var emitter := weapon_emitter_scene.instantiate() as MeleeComboEmitter
	if emitter == null:
		return

	weapon_socket.add_child(emitter)
	emitter.transform = Transform3D.IDENTITY
	_active_weapon_emitter = emitter
	_load_weapon_parameters()


func _load_weapon_parameters() -> void:
	var melee_emitter := _active_weapon_emitter as MeleeComboEmitter
	if melee_emitter == null:
		return

	_weapon_dash_time = maxf(melee_emitter.dash_time, 0.0)
	_weapon_dash_speed = maxf(melee_emitter.dash_speed, 0.0)
	_weapon_dash_speed_curve = melee_emitter.dash_speed_curve


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
	_finish_melee_hit_stop()
	_is_super_attacking = false
	_super_attack_phase = ""
	_super_attack_time_left = 0.0
	_stop_super_charge_effect()
	_shake_camera_on_death()
	_clear_attack_state(true)
	if _is_dashing:
		_stop_dash()
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

	if _uses_animation_tree and _animation_tree != null:
		_play_full_body_attack(super_attack_charge_animation_name)
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
	_face_keyboard_movement(delta)
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
	if _uses_animation_tree and _animation_tree != null:
		_play_full_body_attack(super_attack_shoot_animation_name)
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


func _update_attack_animation(delta: float) -> void:
	if not _is_attacking:
		return

	if _attack_time_left > 0.0:
		_attack_time_left = maxf(_attack_time_left - delta, 0.0)
	if _attack_time_left <= 0.0:
		_finish_attack()


func _update_combo_continue_window(delta: float) -> void:
	if _combo_continue_time_left <= 0.0 or _is_attacking:
		return

	_combo_continue_time_left = maxf(_combo_continue_time_left - maxf(delta, 0.0), 0.0)
	if _combo_continue_time_left <= 0.0:
		_reset_combo_cycle()


func _clear_attack_state(abort_animation: bool) -> void:
	_is_attacking = false
	_attack_time_left = 0.0
	_combo_attack_is_queued = false
	_combo_continue_time_left = 0.0
	_active_combo = null
	_combo_distance_traveled = 0.0
	_combo_move_elapsed = 0.0
	_combo_move_distance_ratio = 0.0
	velocity = Vector3.ZERO
	if _uses_animation_tree and _animation_tree != null:
		_target_attack_layer_blend_amount = 0.0
		if abort_animation:
			_attack_layer_blend_amount = 0.0
			_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)


func _finish_attack() -> void:
	if not _is_attacking:
		return

	if _combo_attack_is_queued:
		var next_combo := _get_next_combo_attack()
		if next_combo != null:
			_play_combo_attack(next_combo)
			return

	_clear_attack_state(false)
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	if combo_emitter != null:
		_combo_continue_time_left = maxf(combo_emitter.combo_continue_time, 0.0)
		if _combo_continue_time_left <= 0.0:
			_reset_combo_cycle()
	_current_animation = ""


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
	if weapon_socket != null:
		spawn_transform = weapon_socket.global_transform

	var shoot_direction := _get_shoot_direction()

	projectile.global_transform = Transform3D(_basis_with_y_axis(shoot_direction), spawn_transform.origin)

	if projectile.has_method("setup"):
		projectile.call("setup", shoot_direction, self)


func _get_shoot_direction() -> Vector3:
	return global_transform.basis.z.normalized()


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


func _spawn_super_shoot_hit_spark() -> void:
	var spawn_position := global_position
	if _active_weapon_emitter != null:
		spawn_position = _active_weapon_emitter.global_position
	elif weapon_socket != null:
		spawn_position = weapon_socket.global_position

	_spawn_hit_spark_at_position(
		super_attack_shoot_hit_spark_scene,
		spawn_position
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


func _face_direction(direction: Vector3, delta: float, turn_speed: float) -> void:
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
	var next_yaw := rotate_toward(current_yaw, target_yaw, maxf(turn_speed, 0.0) * delta)
	var next_direction := Vector3(sin(next_yaw), 0.0, cos(next_yaw)).normalized()
	global_transform = global_transform.looking_at(global_position - next_direction, Vector3.UP)


func _face_keyboard_movement(delta: float) -> void:
	var movement_direction := _get_keyboard_movement()
	if not movement_direction.is_zero_approx():
		_face_direction(movement_direction, delta, face_turn_speed)


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
	if not _has_animation("idle") or not _has_animation("walk") or _get_valid_dash_animation_names().is_empty() or _get_valid_attack_animation_names().is_empty():
		return

	var animation_root := animation_player.get_parent()
	if animation_root == null:
		return
	_animation_tree = animation_root.get_node_or_null("HeroAnimationTree") as AnimationTree
	if _animation_tree == null:
		_animation_tree = AnimationTree.new()
		_animation_tree.name = "HeroAnimationTree"
		animation_root.add_child(_animation_tree)

	var tree_root := AnimationNodeBlendTree.new()
	_animation_tree.tree_root = tree_root
	_animation_tree.anim_player = animation_player.get_path()

	_runtime_dash_animation_name = _get_valid_dash_animation_names()[0]
	_add_animation_tree_animation(tree_root, "Idle", "idle")
	_add_animation_tree_animation(tree_root, "Walk", "walk")
	_dash_animation_node = _add_animation_tree_animation(tree_root, "Dash", _runtime_dash_animation_name)
	var first_attack_animation := _get_valid_attack_animation_names()[0]
	_attack_animation_node_a = _add_animation_tree_animation(tree_root, "AttackA", first_attack_animation)
	_attack_animation_node_b = _add_animation_tree_animation(tree_root, "AttackB", first_attack_animation)

	var locomotion_blend := AnimationNodeBlend2.new()
	locomotion_blend.filter_enabled = false
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

	var attack_blend := AnimationNodeBlend2.new()
	attack_blend.filter_enabled = false
	tree_root.add_node("AttackSeekA", AnimationNodeTimeSeek.new(), Vector2(820.0, 80.0))
	tree_root.connect_node("AttackSeekA", 0, "AttackA")
	tree_root.add_node("AttackSeekB", AnimationNodeTimeSeek.new(), Vector2(820.0, 200.0))
	tree_root.connect_node("AttackSeekB", 0, "AttackB")
	tree_root.add_node("AttackBlend", attack_blend, Vector2(1040.0, 120.0))
	tree_root.connect_node("AttackBlend", 0, "AttackSeekA")
	tree_root.connect_node("AttackBlend", 1, "AttackSeekB")

	var attack_time_scale := AnimationNodeTimeScale.new()
	tree_root.add_node("AttackTimeScale", attack_time_scale, Vector2(1280.0, 120.0))
	tree_root.connect_node("AttackTimeScale", 0, "AttackBlend")

	var attack_layer_blend := AnimationNodeBlend2.new()
	attack_layer_blend.filter_enabled = false
	tree_root.add_node("AttackLayerBlend", attack_layer_blend, Vector2(1520.0, 0.0))
	tree_root.connect_node("AttackLayerBlend", 0, "DashBlend")
	tree_root.connect_node("AttackLayerBlend", 1, "AttackTimeScale")
	tree_root.connect_node("output", 0, "AttackLayerBlend")

	_animation_tree.active = true
	_uses_animation_tree = true
	_animation_tree.set("parameters/LocomotionBlend/blend_amount", _locomotion_blend_amount)
	_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	_animation_tree.set("parameters/AttackBlend/blend_amount", _attack_blend_amount)
	_animation_tree.set("parameters/AttackTimeScale/scale", 1.0)
	_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)
	_set_locomotion_animation("idle")


func _add_animation_tree_animation(tree_root: AnimationNodeBlendTree, node_name: String, animation_name: String) -> AnimationNodeAnimation:
	var animation_node := AnimationNodeAnimation.new()
	animation_node.animation = StringName(animation_name)
	tree_root.add_node(node_name, animation_node)
	return animation_node


func _get_next_combo_attack() -> HeroComboAttack:
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	if combo_emitter == null:
		return null
	return combo_emitter.take_next_combo_attack(animation_player)


func _get_valid_attack_animation_names() -> PackedStringArray:
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	if combo_emitter == null:
		return PackedStringArray()
	return combo_emitter.get_valid_combo_animation_names(animation_player)


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
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	return combo_emitter != null and combo_emitter.is_combo_animation(animation_name)


func _is_dash_animation(animation_name: String) -> bool:
	return animation_name == dash_animation_name or dash_animation_cycle.has(animation_name)


func _play_animation(animation_name: String, force_restart := false) -> void:
	if not _has_animation(animation_name):
		return
	if animation_name == "idle" and _current_animation != "idle" and _combo_continue_time_left <= 0.0:
		_reset_combo_cycle()
	if _uses_animation_tree:
		if _is_attack_animation(animation_name):
			_play_full_body_attack(animation_name)
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


func _reset_combo_cycle() -> void:
	var combo_emitter := _active_weapon_emitter as MeleeComboEmitter
	if combo_emitter != null:
		combo_emitter.reset_combo_cycle()


func _play_full_body_attack(animation_name: String) -> void:
	if _animation_tree == null:
		return

	var runtime_animation_name := StringName(animation_name)
	if _active_attack_blend_slot == 0:
		if _attack_animation_node_b != null:
			_attack_animation_node_b.animation = runtime_animation_name
		_animation_tree.set("parameters/AttackSeekB/seek_request", 0.0)
		_active_attack_blend_slot = 1
		_target_attack_blend_amount = 1.0
	else:
		if _attack_animation_node_a != null:
			_attack_animation_node_a.animation = runtime_animation_name
		_animation_tree.set("parameters/AttackSeekA/seek_request", 0.0)
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
	elif _is_dash_animation(animation_name):
		_target_dash_blend_amount = 1.0
		_dash_blend_amount = 1.0
		_target_attack_layer_blend_amount = 0.0
		_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	elif animation_name == "idle":
		_target_locomotion_blend_amount = 0.0
		_target_dash_blend_amount = 0.0
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
	_attack_blend_amount = move_toward(_attack_blend_amount, _target_attack_blend_amount, blend_step)
	_attack_layer_blend_amount = move_toward(_attack_layer_blend_amount, _target_attack_layer_blend_amount, blend_step)
	_animation_tree.set("parameters/LocomotionBlend/blend_amount", _locomotion_blend_amount)
	_animation_tree.set("parameters/DashBlend/blend_amount", _dash_blend_amount)
	_animation_tree.set("parameters/AttackBlend/blend_amount", _attack_blend_amount)
	_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)


func _has_animation(animation_name: String) -> bool:
	return animation_player != null and animation_player.has_animation(animation_name)
