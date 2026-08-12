extends Node3D

const OVERLAP_AVOIDANCE_GROUP := "enemy_ai_overlap_avoidance"
const HEALTH_BAR_SIZE := Vector2(1.6, 0.18)
const HEALTH_BAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 background_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.9, 0.02, 0.02, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width_pixels = 2.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 outline_size = min(fwidth(UV) * outline_width_pixels, vec2(0.49));
	bool inside_bar = UV.x >= outline_size.x
		&& UV.x <= 1.0 - outline_size.x
		&& UV.y >= outline_size.y
		&& UV.y <= 1.0 - outline_size.y;
	float interior_x = clamp(
		(UV.x - outline_size.x) / max(1.0 - outline_size.x * 2.0, 0.001),
		0.0,
		1.0
	);
	if (!inside_bar) {
		ALBEDO = outline_color.rgb;
	} else {
		ALBEDO = interior_x <= fill_ratio ? fill_color.rgb : background_color.rgb;
	}
	ALPHA = 1.0;
}
"""

static var _shared_health_bar_shader: Shader

@export_group("Animation")
@export var idle_animation_name: String = "idle"
@export var walk_animation_name: String = "walk"
@export var attack_animation_name: String = "idle"
@export var damage_animation_name: String = "damage"
@export var animation_blend_time: float = 0.2

@export_group("Spawn")
@export var spawn_height: float = 0.0

@export_group("Health")
@export var max_health: int = 3
@export var health_bar_height: float = 2.2

@export_group("Movement")
@export var walk_speed: float = 2.0
@export var chase_speed: float = 5.0
@export var turn_speed: float = 8.0
@export var idle_time_range: Vector2 = Vector2(2.0, 4.0)
@export var walk_time_range: Vector2 = Vector2(2.0, 4.0)
@export var run_away_speed: float = 5.0
@export_range(1.0, 10.0, 0.1) var offscreen_speed_multiplier: float = 2.0

@export_group("AI Decision")
@export var use_weighted_ai: bool = false
@export var target_node_name: String = "hero_girl01"
@export var ai_idle_weight: float = 10.0
@export var ai_chase_weight: float = 70.0
@export var ai_attack_weight: float = 30.0
@export var chase_time_range: Vector2 = Vector2(1.0, 2.0)
@export_range(0.0, 45.0, 0.1, "suffix:deg") var chase_direction_angle: float = 12.0
@export var chase_direction_change_time_range: Vector2 = Vector2(0.4, 0.9)

@export_group("Attack State")
@export var attack_time_range: Vector2 = Vector2(0.5, 0.8)
@export var shoot_projectile_scene: PackedScene
@export var shoot_projectile_spawn_paths: Array[NodePath] = []
@export var shoot_projectile_spawn_delay: float = 0.15
@export var shoot_along_face_direction: bool = false

@export_group("Hero Spacing")
@export var avoid_hero_when_too_close: bool = true
@export var minimum_hero_distance: float = 2.0
@export var retreat_from_hero_speed: float = 4.0
@export var retreat_from_hero_duration: float = 0.5

@export_group("Overlap Avoidance")
@export var avoid_enemy_overlap: bool = false
@export var overlap_avoidance_radius: float = 1.2
@export var overlap_avoidance_strength: float = 8.0
@export var overlap_avoidance_max_push_speed: float = 3.0

@export_group("Hit Reaction")
@export var knockback_resistance: float = 1.0
@export var attack_hit_push_distance: float = 1.0
@export var attack_hit_push_duration: float = 0.25
@export var attack_hit_push_slowdown_power: float = 2.0
@export var hit_flash_duration: float = 0.25
@export var hit_flash_power: float = 0.5
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
@export_range(0, 100, 1) var death_drop_quantity: int = 1
@export_range(0.1, 10.0, 0.1, "suffix:m") var death_drop_spacing: float = 1.6
@export var death_drop_ground_offset: float = 0.0

@export_group("")

@onready var visual_root := get_node_or_null("mouse01") as Node3D
@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var player_detection := get_node_or_null("playerdetection") as Area3D

var health := 0
var _health_bar: MeshInstance3D
var _health_bar_material: ShaderMaterial
var _visual_start_scale := Vector3.ONE
var _hit_tween: Tween
var _hit_flash_tween: Tween
var _hit_flash_material: StandardMaterial3D
var _hit_flash_meshes: Array[MeshInstance3D] = []
var _hit_flash_previous_overlays: Array[Material] = []
var _rng := RandomNumberGenerator.new()
var _state := "idle"
var _state_time_left := 0.0
var _walk_direction := Vector3.ZERO
var _chase_direction_angle_offset := 0.0
var _chase_direction_change_time_left := 0.0
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
var _attack_hit_push_direction := Vector3.ZERO
var _attack_hit_push_elapsed := 0.0
var _attack_hit_push_distance_ratio := 0.0
var _attack_hit_push_distance := 0.0
var _attack_hit_push_duration := 0.0
var _attack_hit_push_slowdown_power := 1.0
var _is_dead := false
var _attack_elapsed := 0.0
var _attack_projectile_was_spawned := false
var _shoot_projectile_spawns: Array[Node3D] = []
var _retreat_target: Node3D


func _ready() -> void:
	_rng.randomize()
	health = max_health
	_create_enemy_health_bar()
	if visual_root != null:
		_visual_start_scale = visual_root.scale
	_cache_hit_flash_meshes()
	if player_detection != null:
		player_detection.body_entered.connect(_on_player_detection_body_entered)
		player_detection.body_exited.connect(_on_player_detection_body_exited)
	_cache_shoot_projectile_spawns()
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
	_process_attack_hit_push(delta)
	_apply_overlap_avoidance(delta)
	if _state == "retreat_from_hero":
		_process_retreat_from_hero(delta)
		return
	if _try_start_retreat_from_hero():
		_process_retreat_from_hero(delta)
		return
	if _state == "run_away":
		_process_run_away(delta)
		return
	if _state == "chase":
		_process_chase(delta)
		return
	if _state == "attack":
		_process_attack(delta)
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
		global_position += _walk_direction * walk_speed * _get_offscreen_speed_multiplier() * delta
		_face_direction(_walk_direction, delta)

		if _state_time_left <= 0.0:
			if use_weighted_ai:
				_start_weighted_decision()
			else:
				_start_idle()


func _try_start_retreat_from_hero() -> bool:
	if not avoid_hero_when_too_close or minimum_hero_distance <= 0.0:
		return false

	var hero: Node3D = _find_ai_target()
	if hero == null:
		return false

	var offset: Vector3 = global_position - hero.global_position
	offset.y = 0.0
	if offset.length_squared() >= minimum_hero_distance * minimum_hero_distance:
		return false

	_retreat_target = hero
	_state = "retreat_from_hero"
	_state_time_left = maxf(retreat_from_hero_duration, 0.0)
	_play_animation(walk_animation_name)
	return true


func _process_retreat_from_hero(delta: float) -> void:
	if _retreat_target == null or not is_instance_valid(_retreat_target):
		_finish_retreat_from_hero()
		return

	var retreat_direction: Vector3 = global_position - _retreat_target.global_position
	retreat_direction.y = 0.0
	if retreat_direction == Vector3.ZERO:
		retreat_direction = global_transform.basis.z
	retreat_direction = retreat_direction.normalized()

	global_position += retreat_direction * maxf(retreat_from_hero_speed, 0.0) * _get_offscreen_speed_multiplier() * delta
	_face_direction(retreat_direction, delta)
	_state_time_left -= delta
	if _state_time_left <= 0.0:
		_finish_retreat_from_hero()


func _finish_retreat_from_hero() -> void:
	_retreat_target = null
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
	global_position += run_direction * run_away_speed * _get_offscreen_speed_multiplier() * delta
	_face_direction(run_direction, delta)


func _start_chase(player: Node3D) -> void:
	_detected_player = player
	_state = "chase"
	_state_time_left = _rng.randf_range(chase_time_range.x, chase_time_range.y)
	_randomize_chase_direction()
	_play_animation(walk_animation_name)


func _process_chase(delta: float) -> void:
	if _detected_player == null or not is_instance_valid(_detected_player):
		_detected_player = null
		_start_weighted_decision()
		return

	_state_time_left -= delta
	_chase_direction_change_time_left -= delta
	if _chase_direction_change_time_left <= 0.0:
		_randomize_chase_direction()

	var chase_direction := _detected_player.global_position - global_position
	chase_direction.y = 0.0

	if chase_direction != Vector3.ZERO:
		chase_direction = chase_direction.normalized().rotated(
			Vector3.UP,
			_chase_direction_angle_offset
		)
		global_position += chase_direction * chase_speed * _get_offscreen_speed_multiplier() * delta
		_face_direction(chase_direction, delta)

	if _state_time_left <= 0.0:
		_start_weighted_decision()


func _randomize_chase_direction() -> void:
	var maximum_angle := deg_to_rad(maxf(chase_direction_angle, 0.0))
	_chase_direction_angle_offset = _rng.randf_range(-maximum_angle, maximum_angle)

	var minimum_change_time := maxf(
		minf(chase_direction_change_time_range.x, chase_direction_change_time_range.y),
		0.05
	)
	var maximum_change_time := maxf(
		maxf(chase_direction_change_time_range.x, chase_direction_change_time_range.y),
		minimum_change_time
	)
	_chase_direction_change_time_left = _rng.randf_range(
		minimum_change_time,
		maximum_change_time
	)


func _get_offscreen_speed_multiplier() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 1.0
	if camera.is_position_behind(global_position):
		return maxf(offscreen_speed_multiplier, 1.0)

	var screen_position := camera.unproject_position(global_position)
	if not get_viewport().get_visible_rect().has_point(screen_position):
		return maxf(offscreen_speed_multiplier, 1.0)

	return 1.0


func _start_attack(player: Node3D) -> void:
	_detected_player = player
	_state = "attack"
	_state_time_left = _rng.randf_range(attack_time_range.x, attack_time_range.y)
	_attack_elapsed = 0.0
	_attack_projectile_was_spawned = false
	_play_animation(attack_animation_name, true)


func _process_attack(delta: float) -> void:
	_state_time_left -= delta
	_attack_elapsed += delta

	if _detected_player != null and is_instance_valid(_detected_player):
		var face_direction := _detected_player.global_position - global_position
		face_direction.y = 0.0
		_face_direction(face_direction.normalized(), delta)

	if not _attack_projectile_was_spawned and _attack_elapsed >= shoot_projectile_spawn_delay:
		_spawn_shoot_projectile()

	if _state_time_left <= 0.0:
		_start_idle()


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
	_clear_attack_hit_push()
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


func _start_attack_hit_push(push_direction: Vector3, push_distance: float, push_duration: float, slowdown_power: float) -> void:
	if push_direction == Vector3.ZERO:
		push_direction = global_transform.basis.z

	_attack_hit_push_direction = push_direction.normalized()
	_attack_hit_push_elapsed = 0.0
	_attack_hit_push_distance_ratio = 0.0
	_attack_hit_push_distance = maxf(push_distance, 0.0)
	_attack_hit_push_duration = maxf(push_duration, 0.0)
	_attack_hit_push_slowdown_power = maxf(slowdown_power, 1.0)


func _process_attack_hit_push(delta: float) -> void:
	if _attack_hit_push_duration <= 0.0 or _attack_hit_push_distance <= 0.0:
		return

	_attack_hit_push_elapsed = minf(_attack_hit_push_elapsed + delta, _attack_hit_push_duration)
	var progress: float = _attack_hit_push_elapsed / _attack_hit_push_duration
	var distance_ratio: float = 1.0 - pow(1.0 - progress, _attack_hit_push_slowdown_power)
	var frame_distance: float = (distance_ratio - _attack_hit_push_distance_ratio) * _attack_hit_push_distance

	global_position += _attack_hit_push_direction * frame_distance
	_attack_hit_push_distance_ratio = distance_ratio
	if _attack_hit_push_elapsed >= _attack_hit_push_duration:
		_clear_attack_hit_push()


func _clear_attack_hit_push() -> void:
	_attack_hit_push_direction = Vector3.ZERO
	_attack_hit_push_elapsed = 0.0
	_attack_hit_push_distance_ratio = 0.0
	_attack_hit_push_distance = 0.0
	_attack_hit_push_duration = 0.0


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

	if action == "attack" and _detected_player != null:
		_start_attack(_detected_player)
		return

	_start_idle()


func _pick_weighted_action() -> String:
	var idle_weight := maxf(ai_idle_weight, 0.0)
	var chase_weight := maxf(ai_chase_weight, 0.0)
	var attack_weight := maxf(ai_attack_weight, 0.0)
	var total_weight := idle_weight + chase_weight + attack_weight

	if total_weight <= 0.0:
		return "idle"

	var roll := _rng.randf_range(0.0, total_weight)
	if roll < idle_weight:
		return "idle"

	roll -= idle_weight
	if roll < chase_weight:
		return "chase"

	return "attack"


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
	_attack_projectile_was_spawned = true
	if shoot_projectile_scene == null:
		return

	var projectile_parent: Node = get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_parent()
	if projectile_parent == null:
		projectile_parent = self

	if _shoot_projectile_spawns.is_empty():
		_spawn_shoot_projectile_at(global_transform, projectile_parent)
		return

	for spawn in _shoot_projectile_spawns:
		if spawn == null or not is_instance_valid(spawn):
			continue

		_spawn_shoot_projectile_at(spawn.global_transform, projectile_parent)


func _spawn_shoot_projectile_at(spawn_transform: Transform3D, projectile_parent: Node) -> void:
	var projectile := shoot_projectile_scene.instantiate() as Node3D
	if projectile == null:
		return

	projectile_parent.add_child(projectile)

	var shoot_direction := global_transform.basis.z.normalized()
	if not shoot_along_face_direction and _detected_player != null and is_instance_valid(_detected_player):
		shoot_direction = _detected_player.global_position - spawn_transform.origin
		if shoot_direction == Vector3.ZERO:
			shoot_direction = global_transform.basis.z
		shoot_direction = shoot_direction.normalized()

	projectile.global_transform = Transform3D(_basis_with_y_axis(shoot_direction), spawn_transform.origin)

	if projectile.has_method("setup"):
		projectile.call("setup", shoot_direction, self)


func _cache_shoot_projectile_spawns() -> void:
	_shoot_projectile_spawns.clear()
	for spawn_path in shoot_projectile_spawn_paths:
		if spawn_path == NodePath(""):
			continue

		var spawn := get_node_or_null(spawn_path) as Node3D
		if spawn == null:
			continue

		_shoot_projectile_spawns.append(spawn)


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


func take_attack_hit(direction: Vector3, damage: int, impact_weight: float = 1.0) -> void:
	_apply_damage(damage)
	if health > 0:
		var push_multiplier: float = maxf(impact_weight, 0.0) / maxf(knockback_resistance, 0.1)
		var push_distance: float = attack_hit_push_distance * push_multiplier
		_start_attack_hit_push(direction, push_distance, attack_hit_push_duration, attack_hit_push_slowdown_power)


func take_dash_hit(direction: Vector3, damage: int) -> void:
	_apply_damage(damage)
	if health > 0:
		_start_hit_damage(direction, dash_hit_push_distance, dash_hit_push_duration, dash_hit_push_slowdown_power, dash_hit_damage_duration)


func _apply_damage(damage: int) -> void:
	if _is_dead:
		return

	health = maxi(health - damage, 0)
	_show_enemy_health_bar()
	print("mouse01 took ", damage, " damage. HP: ", health, "/", max_health)
	_show_damage_number(damage)
	_play_hit_feedback()

	if health <= 0:
		_is_dead = true
		_spawn_death_spark()
		_spawn_death_drop()
		queue_free()


func _create_enemy_health_bar() -> void:
	if _shared_health_bar_shader == null:
		_shared_health_bar_shader = Shader.new()
		_shared_health_bar_shader.code = HEALTH_BAR_SHADER_CODE

	var quad := QuadMesh.new()
	quad.size = HEALTH_BAR_SIZE

	_health_bar_material = ShaderMaterial.new()
	_health_bar_material.shader = _shared_health_bar_shader
	_health_bar_material.render_priority = 10
	_health_bar_material.set_shader_parameter("fill_ratio", 1.0)
	_health_bar_material.set_shader_parameter("background_color", Color.BLACK)
	_health_bar_material.set_shader_parameter("fill_color", Color(0.9, 0.02, 0.02, 1.0))
	_health_bar_material.set_shader_parameter("outline_color", Color.BLACK)
	_health_bar_material.set_shader_parameter("outline_width_pixels", 2.0)

	_health_bar = MeshInstance3D.new()
	_health_bar.name = "EnemyHealthBar"
	_health_bar.mesh = quad
	_health_bar.material_override = _health_bar_material
	_health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health_bar.position = Vector3.UP * health_bar_height
	_health_bar.visible = false
	add_child(_health_bar)


func _show_enemy_health_bar() -> void:
	if _health_bar == null or _health_bar_material == null:
		return

	var health_ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
	_health_bar_material.set_shader_parameter("fill_ratio", health_ratio)
	_health_bar.visible = true


func _play_hit_feedback() -> void:
	_play_white_hit_flash()
	if visual_root == null:
		return

	if _hit_tween != null:
		_hit_tween.kill()

	_hit_tween = create_tween()
	var hit_scale := Vector3(_visual_start_scale.x * 1.2, _visual_start_scale.y * 0.75, _visual_start_scale.z * 1.2)
	_hit_tween.tween_property(visual_root, "scale", hit_scale, 0.06)
	_hit_tween.tween_property(visual_root, "scale", _visual_start_scale, 0.12)


func _cache_hit_flash_meshes() -> void:
	_hit_flash_meshes.clear()
	_hit_flash_previous_overlays.clear()
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		if mesh_instance == _health_bar:
			continue
		_hit_flash_meshes.append(mesh_instance)
		_hit_flash_previous_overlays.append(mesh_instance.material_overlay)


func _play_white_hit_flash() -> void:
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

	_hit_flash_material.albedo_color = Color(1.0, 1.0, 1.0, clampf(hit_flash_power, 0.0, 1.0))
	for mesh_instance in _hit_flash_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _hit_flash_material

	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash_material, "albedo_color:a", 0.0, hit_flash_duration)
	_hit_flash_tween.tween_callback(_clear_white_hit_flash)


func _clear_white_hit_flash() -> void:
	for index in range(_hit_flash_meshes.size()):
		var mesh_instance: MeshInstance3D = _hit_flash_meshes[index]
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _hit_flash_previous_overlays[index]


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
	tween.tween_property(label, "outline_modulate:a", 0.0, damage_number_duration)
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
	if death_drop_scene == null or death_drop_quantity <= 0:
		return

	var drop_parent := get_tree().current_scene
	if drop_parent == null:
		drop_parent = get_parent()
	if drop_parent == null:
		return

	var drop_origin := global_position + Vector3.UP * death_drop_ground_offset
	var quantity := maxi(death_drop_quantity, 1)
	var angle_offset := _rng.randf_range(0.0, TAU)
	var ring_radius := 0.0
	if quantity > 1:
		ring_radius = maxf(death_drop_spacing, 0.1) / (2.0 * sin(PI / float(quantity)))

	for drop_index in quantity:
		var angle := angle_offset + TAU * float(drop_index) / float(quantity)
		var drop_direction := Vector3(cos(angle), 0.0, sin(angle))
		var drop_position := drop_origin + drop_direction * ring_radius
		_spawn_death_drop_instance(drop_parent, drop_position, drop_direction)


func _spawn_death_drop_instance(drop_parent: Node, drop_position: Vector3, drop_direction: Vector3) -> void:
	var drop := death_drop_scene.instantiate() as Node3D
	if drop == null:
		return

	drop_parent.add_child(drop)
	drop.global_position = drop_position

	if drop.has_method("pop_from_ground"):
		drop.call("pop_from_ground", drop_position, drop_direction)


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
