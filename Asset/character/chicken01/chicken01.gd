extends CharacterBody3D

@export var move_speed: float = 4.0
@export var turn_speed: float = 12.0
@export var step_height: float = 0.08
@export var step_tilt: float = 0.08
@export var step_speed: float = 10.0
@export var animation_blend_time: float = 0.2
@export var slide_duration: float = 0.3
@export var attack_animation_name: String = "attack01"
@export var attack_damage: int = 1
@export var attack_duration: float = 0.6
@export var attack_hitbox_start: float = 0.2
@export var attack_hitbox_end: float = 0.45
@export var dash_animation_name: String = "dash"
@export var dash_duration: float = 1.0
@export var dash_distance: float = 5.0
@export var dash_damage: int = 1
@export var dash_slowdown_power: float = 4.0
@export var dash_bounce_back_distance: float = 1.4
@export var dash_bounce_back_duration: float = 0.25
@export var dash_bounce_back_slowdown_power: float = 2.5
@export var dash_cooldown: float = 0.5
@export var dash_hit_camera_shake_duration: float = 0.5
@export var dash_hit_camera_shake_strength: float = 0.45
@export var hit_spark_scene: PackedScene
@export var hit_spark_height: float = 0.8

@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var visual_root := get_node_or_null("chicken01") as Node3D
@onready var dash_dust := get_node_or_null("DashDust/GPUParticles3D") as GPUParticles3D
@onready var attack_hitbox := get_node_or_null("AttackHitbox") as Area3D
@onready var attack_hitbox_shape := get_node_or_null("AttackHitbox/CollisionShape3D") as CollisionShape3D
@onready var dash_hitbox := get_node_or_null("DashHitbox") as Area3D
@onready var dash_hitbox_shape := get_node_or_null("DashHitbox/CollisionShape3D") as CollisionShape3D

var _current_animation := ""
var _visual_start_position := Vector3.ZERO
var _visual_start_rotation := Vector3.ZERO
var _walk_time := 0.0
var _last_movement := Vector3.ZERO
var _slide_time_left := 0.0
var _attack_key_was_pressed := false
var _is_attacking := false
var _attack_elapsed := 0.0
var _dash_key_was_pressed := false
var _is_dashing := false
var _dash_time_left := 0.0
var _dash_elapsed := 0.0
var _dash_distance_ratio := 0.0
var _dash_direction := Vector3.ZERO
var _is_dash_bouncing_back := false
var _dash_bounce_elapsed := 0.0
var _dash_bounce_distance_ratio := 0.0
var _dash_cooldown_time_left := 0.0
var _attack_hit_targets: Array[Node] = []
var _dash_hit_targets: Array[Node] = []


func _ready() -> void:
	if visual_root != null:
		_visual_start_position = visual_root.position
		_visual_start_rotation = visual_root.rotation
	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	if attack_hitbox != null:
		attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
		attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)
	if dash_hitbox != null:
		dash_hitbox.body_entered.connect(_on_dash_hitbox_body_entered)
		dash_hitbox.area_entered.connect(_on_dash_hitbox_area_entered)
	_set_attack_hitbox_enabled(false)
	_set_dash_hitbox_enabled(false)
	_stop_dash_dust()
	_play_animation("idle")


func _physics_process(delta: float) -> void:
	_update_dash_cooldown(delta)
	_update_attack_input()
	_update_dash_input()
	_update_attack_hitbox(delta)

	if _is_dashing:
		_process_dash(delta)
		return

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
			_face_direction(movement, delta)
			_animate_walk(delta)
			if not _is_attacking and not _is_dashing:
				_play_animation("walk")
		else:
			_reset_walk_pose(delta)
			if not _is_attacking and not _is_dashing:
				_play_animation("idle")
	else:
		_reset_walk_pose(delta)
		if not _is_attacking and not _is_dashing:
			_play_animation("idle")


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
	var attack_key_is_pressed := Input.is_physical_key_pressed(KEY_UP)

	if attack_key_is_pressed and not _attack_key_was_pressed:
		_start_attack()

	_attack_key_was_pressed = attack_key_is_pressed


func _update_dash_input() -> void:
	var dash_key_is_pressed := Input.is_physical_key_pressed(KEY_DOWN)

	if dash_key_is_pressed and not _dash_key_was_pressed:
		_start_dash()

	_dash_key_was_pressed = dash_key_is_pressed


func _update_dash_cooldown(delta: float) -> void:
	if _dash_cooldown_time_left > 0.0:
		_dash_cooldown_time_left = maxf(_dash_cooldown_time_left - delta, 0.0)


func _start_attack() -> void:
	if _is_dashing:
		return

	_is_attacking = true
	_attack_elapsed = 0.0
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(false)

	if _has_animation(attack_animation_name):
		_play_animation(attack_animation_name, true)


func _start_dash() -> void:
	if _is_dashing:
		return
	if _dash_cooldown_time_left > 0.0:
		return

	_stop_attack()
	_is_dashing = true
	_dash_time_left = dash_duration
	_dash_elapsed = 0.0
	_dash_distance_ratio = 0.0
	_dash_direction = _get_dash_direction()
	_is_dash_bouncing_back = false
	_dash_bounce_elapsed = 0.0
	_dash_bounce_distance_ratio = 0.0
	_last_movement = _dash_direction
	_slide_time_left = 0.0
	_dash_hit_targets.clear()

	_reset_walk_pose(get_physics_process_delta_time())
	_set_dash_hitbox_enabled(true)
	_start_dash_dust()
	_play_animation(dash_animation_name, true)


func _process_dash(delta: float) -> void:
	if _is_dash_bouncing_back:
		_process_dash_bounce_back(delta)
		return

	if dash_duration <= 0.0 or dash_distance <= 0.0:
		_stop_dash()
		return

	_dash_elapsed = minf(_dash_elapsed + delta, dash_duration)
	var progress := _dash_elapsed / dash_duration
	var slowdown_power := maxf(dash_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _dash_distance_ratio) * dash_distance

	_move_with_collision(_dash_direction * frame_distance, delta)
	_dash_distance_ratio = distance_ratio
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)
	_apply_current_dash_overlaps()

	if _dash_time_left <= 0.0:
		_stop_dash()


func _process_dash_bounce_back(delta: float) -> void:
	if dash_bounce_back_duration <= 0.0 or dash_bounce_back_distance <= 0.0:
		_stop_dash()
		return

	_dash_bounce_elapsed = minf(_dash_bounce_elapsed + delta, dash_bounce_back_duration)
	var progress := _dash_bounce_elapsed / dash_bounce_back_duration
	var slowdown_power := maxf(dash_bounce_back_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _dash_bounce_distance_ratio) * dash_bounce_back_distance

	_move_with_collision(-_dash_direction * frame_distance, delta)
	_dash_bounce_distance_ratio = distance_ratio

	if _dash_bounce_elapsed >= dash_bounce_back_duration:
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


func _get_dash_direction() -> Vector3:
	return global_transform.basis.z.normalized()


func _move_with_collision(displacement: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return

	velocity = displacement / delta
	velocity.y = 0.0
	move_and_slide()
	velocity = Vector3.ZERO


func _update_attack_hitbox(delta: float) -> void:
	if not _is_attacking:
		_set_attack_hitbox_enabled(false)
		return

	var attack_time := 0.0
	if _has_animation(attack_animation_name) and animation_player.current_animation == StringName(attack_animation_name):
		attack_time = animation_player.current_animation_position
	else:
		_attack_elapsed += delta
		attack_time = _attack_elapsed

		if _attack_elapsed >= attack_duration:
			_stop_attack()
			_current_animation = ""
			return

	var hitbox_is_active := attack_time >= attack_hitbox_start and attack_time <= attack_hitbox_end
	_set_attack_hitbox_enabled(hitbox_is_active)

	if hitbox_is_active:
		_apply_current_attack_overlaps()


func _stop_attack() -> void:
	_is_attacking = false
	_attack_elapsed = 0.0
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(false)


func _set_attack_hitbox_enabled(is_enabled: bool) -> void:
	if attack_hitbox != null:
		attack_hitbox.set_deferred("monitoring", is_enabled)
	if attack_hitbox_shape != null:
		attack_hitbox_shape.set_deferred("disabled", not is_enabled)


func _set_dash_hitbox_enabled(is_enabled: bool) -> void:
	if dash_hitbox != null:
		dash_hitbox.set_deferred("monitoring", is_enabled)
	if dash_hitbox_shape != null:
		dash_hitbox_shape.set_deferred("disabled", not is_enabled)


func _apply_current_attack_overlaps() -> void:
	if attack_hitbox == null:
		return
	if not attack_hitbox.monitoring:
		return

	for body in attack_hitbox.get_overlapping_bodies():
		_apply_attack_hit(body)
	for area in attack_hitbox.get_overlapping_areas():
		_apply_attack_hit(area)


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	_apply_attack_hit(body)


func _on_attack_hitbox_area_entered(area: Area3D) -> void:
	_apply_attack_hit(area)


func _apply_attack_hit(target: Node) -> void:
	if not _is_attacking:
		return
	if target == self or is_ancestor_of(target) or target.is_ancestor_of(self):
		return
	if _attack_hit_targets.has(target):
		return

	_attack_hit_targets.append(target)
	if target.has_method("take_damage"):
		target.call("take_damage", attack_damage)
		_spawn_hit_spark(target)


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
	if target.has_method("take_dash_hit"):
		target.call("take_dash_hit", _dash_direction, dash_damage)
		_spawn_hit_spark(target)
		_shake_camera_on_dash_hit()
		_start_dash_bounce_back()
	elif target.has_method("take_damage"):
		target.call("take_damage", dash_damage)
		_spawn_hit_spark(target)
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


func _spawn_hit_spark(target: Node) -> void:
	if hit_spark_scene == null:
		return
	if not target is Node3D:
		return

	var hit_spark := hit_spark_scene.instantiate() as Node3D
	if hit_spark == null:
		return

	var spark_parent := get_tree().current_scene
	if spark_parent == null:
		spark_parent = self

	spark_parent.add_child(hit_spark)
	hit_spark.global_position = (target as Node3D).global_position + Vector3.UP * hit_spark_height

	var particles := hit_spark.find_child("GPUParticles3D", true, false) as GPUParticles3D
	if particles != null:
		particles.emitting = false
		particles.restart()
		particles.emitting = true
		hit_spark.get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(hit_spark.queue_free)
	else:
		hit_spark.get_tree().create_timer(1.0).timeout.connect(hit_spark.queue_free)


func _start_dash_dust() -> void:
	if dash_dust == null:
		return

	dash_dust.global_position = global_position
	dash_dust.emitting = false
	dash_dust.restart()
	dash_dust.emitting = true


func _stop_dash_dust() -> void:
	if dash_dust == null:
		return

	dash_dust.emitting = false


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_transform := global_transform.looking_at(global_position - direction, Vector3.UP)
	var blend := clampf(turn_speed * delta, 0.0, 1.0)
	global_transform = Transform3D(global_transform.basis.slerp(target_transform.basis, blend), global_position)


func _animate_walk(delta: float) -> void:
	if visual_root == null:
		return

	_walk_time += delta * step_speed
	visual_root.position = _visual_start_position + Vector3.UP * absf(sin(_walk_time)) * step_height
	visual_root.rotation = _visual_start_rotation + Vector3(0.0, 0.0, sin(_walk_time) * step_tilt)


func _reset_walk_pose(delta: float) -> void:
	if visual_root == null:
		return

	_walk_time = 0.0
	var blend := clampf(delta * step_speed, 0.0, 1.0)
	visual_root.position = visual_root.position.lerp(_visual_start_position, blend)
	visual_root.rotation = visual_root.rotation.lerp(_visual_start_rotation, blend)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == StringName(attack_animation_name):
		_stop_attack()
		_current_animation = ""
	if animation_name == StringName(dash_animation_name):
		_current_animation = ""


func _play_animation(animation_name: String, force_restart := false) -> void:
	if not _has_animation(animation_name):
		return
	if _current_animation == animation_name and not force_restart:
		return

	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name


func _has_animation(animation_name: String) -> bool:
	return animation_player != null and animation_player.has_animation(animation_name)
