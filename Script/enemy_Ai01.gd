extends Node3D

const OVERLAP_AVOIDANCE_GROUP := "enemy_ai_overlap_avoidance"

@export_group("Animation")
@export var idle_animation_name: String = "idle"
@export var walk_animation_name: String = "walk"
@export var damage_animation_name: String = "damage"
@export var animation_blend_time: float = 0.2

@export_group("Health")
@export var max_health: int = 3

@export_group("Movement")
@export var walk_speed: float = 2.0
@export var turn_speed: float = 8.0
@export var idle_time_range: Vector2 = Vector2(2.0, 4.0)
@export var walk_time_range: Vector2 = Vector2(2.0, 4.0)
@export var run_away_speed: float = 5.0

@export_group("AI Decision")
@export var use_weighted_ai: bool = false
@export var target_node_name: String = "hero_girl01"
@export var ai_idle_weight: float = 10.0
@export var ai_chase_weight: float = 70.0
@export var ai_shoot_weight: float = 30.0
@export var chase_speed: float = 5.0
@export var chase_time_range: Vector2 = Vector2(1.0, 2.0)
@export var shoot_animation_name: String = "idle"
@export var shoot_time_range: Vector2 = Vector2(0.5, 0.8)
@export var shoot_projectile_scene: PackedScene
@export var shoot_projectile_spawn_path: NodePath = NodePath("")
@export var shoot_projectile_spawn_delay: float = 0.15

@export_group("Overlap Avoidance")
@export var avoid_enemy_overlap: bool = false
@export var overlap_avoidance_radius: float = 1.2
@export var overlap_avoidance_strength: float = 8.0
@export var overlap_avoidance_max_push_speed: float = 3.0

@export_group("Hit Reaction")
@export var attack_hit_push_distance: float = 1.0
@export var attack_hit_push_duration: float = 0.25
@export var attack_hit_push_slowdown_power: float = 2.0
@export var attack_hit_damage_duration: float = 0.35
@export var face_hit_push_direction: bool = true
@export var dash_hit_push_distance: float = 3.0
@export var dash_hit_push_duration: float = 0.5
@export var dash_hit_push_slowdown_power: float = 3.0
@export var dash_hit_damage_duration: float = 1.0

@export_group("Damage Number")
@export var damage_number_height: float = 1.6
@export var damage_number_rise: float = 1.0
@export var damage_number_duration: float = 0.7
@export var damage_number_font: Font
@export var damage_number_font_size: int = 48
@export var damage_number_color := Color(1.0, 0.18, 0.08, 1.0)

@export_group("Death Spark")
@export var death_spark_scene: PackedScene
@export var death_spark_height: float = 0.8

@export_group("Death Drop")
@export var death_drop_scene: PackedScene
@export var death_drop_ground_offset: float = 0.0

@export_group("")

@onready var visual_root := get_node_or_null("mouse01") as Node3D
@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var player_detection := get_node_or_null("playerdetection") as Area3D
@onready var shoot_projectile_spawn := get_node_or_null(shoot_projectile_spawn_path) as Node3D

var health := 0
var _visual_start_scale := Vector3.ONE
var _hit_tween: Tween
var _rng := RandomNumberGenerator.new()
var _state := "idle"
var _state_time_left := 0.0
var _walk_direction := Vector3.ZERO
var _current_animation := ""
var _detected_player: Node3D
var _damage_state_time_left := 0.0
var _damage_push_direction := Vector3.ZERO
var _damage_push_elapsed := 0.0
var _damage_push_distance_ratio := 0.0
var _damage_push_distance := 0.0
var _damage_push_duration := 0.0
var _damage_push_slowdown_power := 1.0
var _damage_hold_duration := 0.0
var _is_dead := false
var _shoot_elapsed := 0.0
var _shoot_projectile_was_spawned := false


func _ready() -> void:
	_rng.randomize()
	health = max_health
	if visual_root != null:
		_visual_start_scale = visual_root.scale
	if player_detection != null:
		player_detection.body_entered.connect(_on_player_detection_body_entered)
		player_detection.body_exited.connect(_on_player_detection_body_exited)
	if avoid_enemy_overlap:
		add_to_group(OVERLAP_AVOIDANCE_GROUP)
	if use_weighted_ai:
		_start_weighted_decision()
	else:
		_start_idle()


func _physics_process(delta: float) -> void:
	if _state == "dash_damage_push":
		_process_dash_damage_push(delta)
		return
	if _state == "dash_damage_hold":
		_process_dash_damage_hold(delta)
		return
	_apply_overlap_avoidance(delta)
	if _state == "run_away":
		_process_run_away(delta)
		return
	if _state == "chase":
		_process_chase(delta)
		return
	if _state == "shoot":
		_process_shoot(delta)
		return

	_state_time_left -= delta

	if _state == "idle":
		if _state_time_left <= 0.0:
			if use_weighted_ai:
				_start_weighted_decision()
			else:
				_start_walk()
		return

	if _state == "walk":
		global_position += _walk_direction * walk_speed * delta
		_face_direction(_walk_direction, delta)

		if _state_time_left <= 0.0:
			if use_weighted_ai:
				_start_weighted_decision()
			else:
				_start_idle()


func _start_run_away(player: Node3D) -> void:
	_detected_player = player
	_state = "run_away"
	_state_time_left = 0.0
	_play_animation(walk_animation_name)


func _process_run_away(delta: float) -> void:
	if _detected_player == null or not is_instance_valid(_detected_player):
		_detected_player = null
		_resume_idle_or_run_away()
		return

	var run_direction := global_position - _detected_player.global_position
	run_direction.y = 0.0

	if run_direction == Vector3.ZERO:
		run_direction = global_transform.basis.z

	run_direction = run_direction.normalized()
	global_position += run_direction * run_away_speed * delta
	_face_direction(run_direction, delta)


func _start_chase(player: Node3D) -> void:
	_detected_player = player
	_state = "chase"
	_state_time_left = _rng.randf_range(chase_time_range.x, chase_time_range.y)
	_play_animation(walk_animation_name)


func _process_chase(delta: float) -> void:
	if _detected_player == null or not is_instance_valid(_detected_player):
		_detected_player = null
		_start_weighted_decision()
		return

	_state_time_left -= delta

	var chase_direction := _detected_player.global_position - global_position
	chase_direction.y = 0.0

	if chase_direction != Vector3.ZERO:
		chase_direction = chase_direction.normalized()
		global_position += chase_direction * chase_speed * delta
		_face_direction(chase_direction, delta)

	if _state_time_left <= 0.0:
		_start_weighted_decision()


func _start_shoot(player: Node3D) -> void:
	_detected_player = player
	_state = "shoot"
	_state_time_left = _rng.randf_range(shoot_time_range.x, shoot_time_range.y)
	_shoot_elapsed = 0.0
	_shoot_projectile_was_spawned = false
	_play_animation(shoot_animation_name, true)


func _process_shoot(delta: float) -> void:
	_state_time_left -= delta
	_shoot_elapsed += delta

	if _detected_player != null and is_instance_valid(_detected_player):
		var face_direction := _detected_player.global_position - global_position
		face_direction.y = 0.0
		_face_direction(face_direction.normalized(), delta)

	if not _shoot_projectile_was_spawned and _shoot_elapsed >= shoot_projectile_spawn_delay:
		_spawn_shoot_projectile()

	if _state_time_left <= 0.0:
		_start_weighted_decision()


func _apply_overlap_avoidance(delta: float) -> void:
	if not avoid_enemy_overlap:
		return
	if overlap_avoidance_radius <= 0.0:
		return

	var separation := Vector3.ZERO
	for node in get_tree().get_nodes_in_group(OVERLAP_AVOIDANCE_GROUP):
		var other: Node3D = node as Node3D
		if other == null or other == self:
			continue
		if not is_instance_valid(other):
			continue

		var offset := global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			offset = global_transform.basis.x * _get_overlap_tiebreak_sign(other)
			offset.y = 0.0
			distance = 0.001

		if distance >= overlap_avoidance_radius:
			continue

		var push_ratio := (overlap_avoidance_radius - distance) / overlap_avoidance_radius
		separation += offset.normalized() * push_ratio

	if separation == Vector3.ZERO:
		return

	var push_velocity := separation * overlap_avoidance_strength
	var push_speed := minf(push_velocity.length(), overlap_avoidance_max_push_speed)
	global_position += push_velocity.normalized() * push_speed * delta


func _get_overlap_tiebreak_sign(other: Node3D) -> float:
	if get_instance_id() < other.get_instance_id():
		return -1.0

	return 1.0


func _stop_run_away(player: Node3D) -> void:
	if player != _detected_player:
		return

	_detected_player = null
	_resume_idle_or_run_away()


func _start_hit_damage(push_direction: Vector3, push_distance: float, push_duration: float, slowdown_power: float, hold_duration: float) -> void:
	if push_direction == Vector3.ZERO:
		push_direction = global_transform.basis.z

	_detected_player = null
	_state = "dash_damage_push"
	_damage_state_time_left = push_duration
	_damage_push_direction = push_direction.normalized()
	_damage_push_elapsed = 0.0
	_damage_push_distance_ratio = 0.0
	_damage_push_distance = push_distance
	_damage_push_duration = push_duration
	_damage_push_slowdown_power = slowdown_power
	_damage_hold_duration = hold_duration
	_play_animation(damage_animation_name, true)


func _process_dash_damage_push(delta: float) -> void:
	if _damage_push_duration <= 0.0 or _damage_push_distance <= 0.0:
		_start_dash_damage_hold()
		return

	_damage_push_elapsed = minf(_damage_push_elapsed + delta, _damage_push_duration)
	var progress := _damage_push_elapsed / _damage_push_duration
	var slowdown_power := maxf(_damage_push_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _damage_push_distance_ratio) * _damage_push_distance

	global_position += _damage_push_direction * frame_distance
	if face_hit_push_direction:
		_face_direction(_damage_push_direction, delta)
	_damage_push_distance_ratio = distance_ratio
	_damage_state_time_left -= delta

	if _damage_state_time_left <= 0.0:
		_start_dash_damage_hold()


func _start_dash_damage_hold() -> void:
	_state = "dash_damage_hold"
	_damage_state_time_left = _damage_hold_duration
	_damage_push_direction = Vector3.ZERO
	_damage_push_elapsed = 0.0
	_damage_push_distance_ratio = 0.0
	_play_animation(damage_animation_name, true)


func _process_dash_damage_hold(delta: float) -> void:
	_damage_state_time_left -= delta

	if _damage_state_time_left <= 0.0:
		_resume_idle_or_run_away()


func _resume_idle_or_run_away() -> void:
	if use_weighted_ai:
		_start_weighted_decision()
		return

	var player := _find_detected_chicken()
	if player != null:
		_start_run_away(player)
	else:
		_start_idle()


func _start_idle() -> void:
	_state = "idle"
	_state_time_left = _rng.randf_range(idle_time_range.x, idle_time_range.y)
	_walk_direction = Vector3.ZERO
	_play_animation(idle_animation_name)


func _start_walk() -> void:
	_state = "walk"
	_state_time_left = _rng.randf_range(walk_time_range.x, walk_time_range.y)
	_walk_direction = _get_random_walk_direction()
	_play_animation(walk_animation_name)


func _start_weighted_decision() -> void:
	_detected_player = _find_ai_target()
	var action := _pick_weighted_action()

	if action == "chase" and _detected_player != null:
		_start_chase(_detected_player)
		return

	if action == "shoot" and _detected_player != null:
		_start_shoot(_detected_player)
		return

	_start_idle()


func _pick_weighted_action() -> String:
	var idle_weight := maxf(ai_idle_weight, 0.0)
	var chase_weight := maxf(ai_chase_weight, 0.0)
	var shoot_weight := maxf(ai_shoot_weight, 0.0)
	var total_weight := idle_weight + chase_weight + shoot_weight

	if total_weight <= 0.0:
		return "idle"

	var roll := _rng.randf_range(0.0, total_weight)
	if roll < idle_weight:
		return "idle"

	roll -= idle_weight
	if roll < chase_weight:
		return "chase"

	return "shoot"


func _get_random_walk_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return

	var target_transform := global_transform.looking_at(global_position - direction, Vector3.UP)
	var blend := clampf(turn_speed * delta, 0.0, 1.0)
	global_transform = Transform3D(global_transform.basis.slerp(target_transform.basis, blend), global_position)


func _on_player_detection_body_entered(body: Node3D) -> void:
	if use_weighted_ai:
		return
	if _state == "dash_damage_push" or _state == "dash_damage_hold":
		return

	var player := _get_detected_chicken(body)
	if player != null:
		_start_run_away(player)


func _on_player_detection_body_exited(body: Node3D) -> void:
	if use_weighted_ai:
		return

	var player := _get_detected_chicken(body)
	if player != null:
		_stop_run_away(player)


func _get_detected_chicken(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current.name == "chicken01" and current is Node3D:
			return current as Node3D
		current = current.get_parent()

	return null


func _find_detected_chicken() -> Node3D:
	if player_detection == null:
		return null
	if not player_detection.monitoring:
		return null

	for body in player_detection.get_overlapping_bodies():
		var player := _get_detected_chicken(body)
		if player != null:
			return player

	return null


func _find_ai_target() -> Node3D:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null

	var target := scene_root.find_child(target_node_name, true, false)
	if target is Node3D:
		return target as Node3D

	return null


func _spawn_shoot_projectile() -> void:
	_shoot_projectile_was_spawned = true
	if shoot_projectile_scene == null:
		return

	var projectile := shoot_projectile_scene.instantiate() as Node3D
	if projectile == null:
		return

	var projectile_parent := get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_parent()
	if projectile_parent == null:
		projectile_parent = self

	projectile_parent.add_child(projectile)

	var spawn_transform := global_transform
	if shoot_projectile_spawn != null:
		spawn_transform = shoot_projectile_spawn.global_transform

	var shoot_direction := global_transform.basis.z.normalized()
	if _detected_player != null and is_instance_valid(_detected_player):
		shoot_direction = _detected_player.global_position - spawn_transform.origin
		if shoot_direction == Vector3.ZERO:
			shoot_direction = global_transform.basis.z
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


func take_damage(damage: int) -> void:
	_apply_damage(damage)


func take_attack_hit(direction: Vector3, damage: int) -> void:
	_apply_damage(damage)
	if health > 0:
		_start_hit_damage(direction, attack_hit_push_distance, attack_hit_push_duration, attack_hit_push_slowdown_power, attack_hit_damage_duration)


func take_dash_hit(direction: Vector3, damage: int) -> void:
	_apply_damage(damage)
	if health > 0:
		_start_hit_damage(direction, dash_hit_push_distance, dash_hit_push_duration, dash_hit_push_slowdown_power, dash_hit_damage_duration)


func _apply_damage(damage: int) -> void:
	if _is_dead:
		return

	health = maxi(health - damage, 0)
	print("mouse01 took ", damage, " damage. HP: ", health, "/", max_health)
	_show_damage_number(damage)
	_play_hit_feedback()

	if health <= 0:
		_is_dead = true
		_spawn_death_spark()
		_spawn_death_drop()
		queue_free()


func _play_hit_feedback() -> void:
	if visual_root == null:
		return

	if _hit_tween != null:
		_hit_tween.kill()

	_hit_tween = create_tween()
	var hit_scale := Vector3(_visual_start_scale.x * 1.2, _visual_start_scale.y * 0.75, _visual_start_scale.z * 1.2)
	_hit_tween.tween_property(visual_root, "scale", hit_scale, 0.06)
	_hit_tween.tween_property(visual_root, "scale", _visual_start_scale, 0.12)


func _show_damage_number(damage: int) -> void:
	var label := Label3D.new()
	label.text = str(damage)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	if damage_number_font != null:
		label.font = damage_number_font
	label.font_size = damage_number_font_size
	label.modulate = damage_number_color
	label.outline_size = 16
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)

	var label_parent := get_tree().current_scene
	if label_parent == null:
		label_parent = self

	label_parent.add_child(label)
	label.global_position = global_position + Vector3.UP * damage_number_height

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3.UP * damage_number_rise, damage_number_duration)
	tween.tween_property(label, "modulate:a", 0.0, damage_number_duration)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


func _spawn_death_spark() -> void:
	if death_spark_scene == null:
		return

	var death_spark := death_spark_scene.instantiate() as Node3D
	if death_spark == null:
		return

	var spark_parent := get_tree().current_scene
	if spark_parent == null:
		spark_parent = get_parent()
	if spark_parent == null:
		return

	spark_parent.add_child(death_spark)
	death_spark.global_position = global_position + Vector3.UP * death_spark_height

	var longest_lifetime := _restart_particles_recursive(death_spark)

	death_spark.get_tree().create_timer(longest_lifetime + 0.1).timeout.connect(death_spark.queue_free)


func _spawn_death_drop() -> void:
	if death_drop_scene == null:
		return

	var drop := death_drop_scene.instantiate() as Node3D
	if drop == null:
		return

	var drop_parent := get_tree().current_scene
	if drop_parent == null:
		drop_parent = get_parent()
	if drop_parent == null:
		return

	drop_parent.add_child(drop)
	var drop_position := global_position + Vector3.UP * death_drop_ground_offset
	drop.global_position = drop_position

	if drop.has_method("pop_from_ground"):
		drop.call("pop_from_ground", drop_position)


func _restart_particles_recursive(node: Node) -> float:
	var longest_lifetime := 1.0

	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.restart()
		particles.emitting = true
		longest_lifetime = maxf(longest_lifetime, particles.lifetime)

	for child in node.get_children():
		longest_lifetime = maxf(longest_lifetime, _restart_particles_recursive(child))

	return longest_lifetime


func _play_animation(animation_name: String, force_restart := false) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(animation_name):
		return
	if _current_animation == animation_name and not force_restart:
		return

	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name
