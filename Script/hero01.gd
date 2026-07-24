extends CharacterBody3D

@export var move_speed: float = 4.0
@export var turn_speed: float = 12.0
@export var step_height: float = 0.08
@export var step_tilt: float = 0.08
@export var step_speed: float = 10.0
@export var animation_blend_time: float = 0.2
@export var slide_duration: float = 0.3

@export_group("Attack")
@export var attack_animation_name: String = "attack01"
@export var attack_idle_animation_name: String = "attack_idle"
@export var attack_animation_cycle: PackedStringArray = PackedStringArray(["attack01", "attack02"])
@export var attack_damage: int = 1
@export var attack_duration: float = 0.6
@export var attack_hitbox_start: float = 0.2
@export var attack_hitbox_end: float = 0.45
@export var attack_dash_distance: float = 0.0
@export var attack_dash_duration: float = 0.18
@export var attack_dash_slowdown_power: float = 2.0
@export var attack_projectile_scene: PackedScene
@export var attack_projectile_spawn_path: NodePath = NodePath("shootposition")
@export var attack_projectile_spawn_time: float = 0.05
@export var attack_upper_body_bone_name: String = "spline1"
@export var attack_lower_body_bone_name: String = "pelvis"

@export_group("")

@export_group("Dash")
@export var dash_animation_name: String = "dash"
@export var dash_animation_cycle: PackedStringArray = PackedStringArray(["dash", "dash02"])
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
@export var dash_dust_scene: PackedScene

@export_group("")

@export_group("Hit Spark")
@export var hit_spark_scene: PackedScene
@export var hit_spark_height: float = 0.8

@export_group("")

@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
@onready var visual_root := get_node_or_null("chicken01") as Node3D
@onready var dash_dust_template := get_node_or_null("DashDust") as Node3D
@onready var attack_hitbox := get_node_or_null("AttackHitbox") as Area3D
@onready var attack_hitbox_shape := get_node_or_null("AttackHitbox/CollisionShape3D") as CollisionShape3D
@onready var attack_projectile_spawn := get_node_or_null(attack_projectile_spawn_path) as Node3D
@onready var dash_hitbox := get_node_or_null("DashHitbox") as Area3D
@onready var dash_hitbox_shape := get_node_or_null("DashHitbox/CollisionShape3D") as CollisionShape3D

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
var _visual_start_position := Vector3.ZERO
var _visual_start_rotation := Vector3.ZERO
var _walk_time := 0.0
var _last_movement := Vector3.ZERO
var _slide_time_left := 0.0
var _attack_key_was_pressed := false
var _is_attacking := false
var _attack_elapsed := 0.0
var _active_attack_animation_name := ""
var _queued_attack_animation_name := ""
var _next_attack_animation_index := 0
var _attack_dash_elapsed := 0.0
var _attack_dash_distance_ratio := 0.0
var _attack_projectile_was_spawned := false
var _dash_key_was_pressed := false
var _is_dashing := false
var _active_dash_animation_name := ""
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
var _attack_hit_targets: Array[Node] = []
var _dash_hit_targets: Array[Node] = []


func _ready() -> void:
	if visual_root != null:
		_visual_start_position = visual_root.position
		_visual_start_rotation = visual_root.rotation
	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	_setup_animation_tree()
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
	_update_animation_tree_blends(delta)
	_update_attack_input()
	_update_attack_hitbox(delta)

	_update_dash_input()

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
			if not _is_dashing:
				_play_animation("walk")
		else:
			_reset_walk_pose(delta)
			if not _is_dashing:
				_play_animation("idle")
	else:
		_reset_walk_pose(delta)
		if not _is_dashing:
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
	_attack_elapsed = 0.0
	_active_attack_animation_name = animation_name
	_attack_dash_elapsed = 0.0
	_attack_dash_distance_ratio = 0.0
	_attack_projectile_was_spawned = false
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(false)

	_play_animation(_active_attack_animation_name, true)


func _start_dash() -> void:
	if _is_dashing:
		return
	if _is_attacking:
		return
	if _dash_cooldown_time_left > 0.0:
		return

	var selected_dash_animation := _get_next_dash_animation_name()
	if selected_dash_animation == "":
		return

	_stop_attack()
	_is_dashing = true
	_active_dash_animation_name = selected_dash_animation
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
	_play_animation(_active_dash_animation_name, true)


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
	_active_dash_animation_name = ""
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
	if _active_attack_animation_name != "" and _has_animation(_active_attack_animation_name) and animation_player.current_animation == StringName(_active_attack_animation_name):
		attack_time = animation_player.current_animation_position
	else:
		_attack_elapsed += delta
		attack_time = _attack_elapsed

		if _attack_elapsed >= attack_duration:
			_finish_attack()
			return

	if not _attack_projectile_was_spawned and attack_time >= attack_projectile_spawn_time:
		_spawn_attack_projectile()

	var hitbox_is_active := attack_projectile_scene == null and attack_time >= attack_hitbox_start and attack_time <= attack_hitbox_end
	_set_attack_hitbox_enabled(hitbox_is_active)

	if hitbox_is_active:
		_apply_current_attack_overlaps()


func _stop_attack() -> void:
	_clear_attack_state(true)


func _clear_attack_state(abort_animation: bool) -> void:
	_is_attacking = false
	_attack_elapsed = 0.0
	_active_attack_animation_name = ""
	_queued_attack_animation_name = ""
	_attack_dash_elapsed = 0.0
	_attack_dash_distance_ratio = 0.0
	_attack_projectile_was_spawned = false
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	if _uses_animation_tree and _animation_tree != null:
		_target_attack_layer_blend_amount = 0.0
		if abort_animation:
			_attack_layer_blend_amount = 0.0
			_animation_tree.set("parameters/AttackLayerBlend/blend_amount", _attack_layer_blend_amount)


func _finish_attack() -> void:
	var next_attack_animation := _queued_attack_animation_name
	_queued_attack_animation_name = ""

	if next_attack_animation != "":
		_play_attack_animation(next_attack_animation)
		return

	_clear_attack_state(false)
	_current_animation = ""


func _process_attack_dash(delta: float) -> void:
	if attack_dash_duration <= 0.0 or attack_dash_distance <= 0.0:
		return
	if _attack_dash_elapsed >= attack_dash_duration:
		return

	_attack_dash_elapsed = minf(_attack_dash_elapsed + delta, attack_dash_duration)
	var progress := _attack_dash_elapsed / attack_dash_duration
	var slowdown_power := maxf(attack_dash_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _attack_dash_distance_ratio) * attack_dash_distance

	_move_with_collision(global_transform.basis.z.normalized() * frame_distance, delta)
	_attack_dash_distance_ratio = distance_ratio


func _spawn_attack_projectile() -> void:
	_attack_projectile_was_spawned = true
	if attack_projectile_scene == null:
		return

	var projectile := attack_projectile_scene.instantiate() as Node3D
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
	projectile.global_transform = Transform3D(_basis_with_y_axis(shoot_direction), spawn_transform.origin)

	if projectile.has_method("setup"):
		projectile.call("setup", shoot_direction, attack_damage, self)


func _basis_with_y_axis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var helper_axis := Vector3.UP
	if absf(y_axis.dot(helper_axis)) > 0.98:
		helper_axis = Vector3.RIGHT

	var x_axis := helper_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


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
	if target.has_method("take_attack_hit"):
		target.call("take_attack_hit", global_transform.basis.z.normalized(), attack_damage)
		_spawn_hit_spark(target)
	elif target.has_method("take_damage"):
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
	var attack_names := PackedStringArray()
	for animation_name in attack_animation_cycle:
		if animation_name != "" and _has_animation(animation_name):
			attack_names.append(animation_name)

	if attack_names.is_empty() and attack_animation_name != "" and _has_animation(attack_animation_name):
		attack_names.append(attack_animation_name)

	return attack_names


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
	var dash_names := PackedStringArray()
	for animation_name in dash_animation_cycle:
		if animation_name != "" and _has_animation(animation_name):
			dash_names.append(animation_name)

	if dash_names.is_empty() and dash_animation_name != "" and _has_animation(dash_animation_name):
		dash_names.append(dash_animation_name)

	return dash_names


func _is_attack_animation(animation_name: String) -> bool:
	if animation_name == attack_animation_name:
		return true

	for cycle_animation_name in attack_animation_cycle:
		if animation_name == cycle_animation_name:
			return true

	return false


func _is_dash_animation(animation_name: String) -> bool:
	if animation_name == dash_animation_name:
		return true

	for cycle_animation_name in dash_animation_cycle:
		if animation_name == cycle_animation_name:
			return true

	return false


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
