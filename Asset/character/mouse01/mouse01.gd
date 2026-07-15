extends Node3D

@export var max_health: int = 3
@export var walk_speed: float = 2.0
@export var turn_speed: float = 8.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 4.0
@export var walk_time_min: float = 2.0
@export var walk_time_max: float = 4.0
@export var run_away_speed: float = 5.0
@export var dash_hit_push_distance: float = 3.0
@export var dash_hit_push_duration: float = 0.5
@export var dash_hit_push_slowdown_power: float = 3.0
@export var dash_hit_damage_duration: float = 1.0
@export var idle_animation_name: String = "idle"
@export var walk_animation_name: String = "walk"
@export var damage_animation_name: String = "damage"
@export var animation_blend_time: float = 0.2
@export var damage_number_height: float = 1.6
@export var damage_number_rise: float = 1.0
@export var damage_number_duration: float = 0.7
@export var damage_number_font: Font
@export var damage_number_font_size: int = 48
@export var damage_number_color := Color(1.0, 0.18, 0.08, 1.0)
@export var death_spark_scene: PackedScene
@export var death_spark_height: float = 0.8

@onready var visual_root := get_node_or_null("mouse01") as Node3D
@onready var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var player_detection := get_node_or_null("playerdetection") as Area3D

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
var _is_dead := false


func _ready() -> void:
	_rng.randomize()
	health = max_health
	if visual_root != null:
		_visual_start_scale = visual_root.scale
	if player_detection != null:
		player_detection.body_entered.connect(_on_player_detection_body_entered)
		player_detection.body_exited.connect(_on_player_detection_body_exited)
	_start_idle()


func _physics_process(delta: float) -> void:
	if _state == "dash_damage_push":
		_process_dash_damage_push(delta)
		return
	if _state == "dash_damage_hold":
		_process_dash_damage_hold(delta)
		return
	if _state == "run_away":
		_process_run_away(delta)
		return

	_state_time_left -= delta

	if _state == "idle":
		if _state_time_left <= 0.0:
			_start_walk()
		return

	if _state == "walk":
		global_position += _walk_direction * walk_speed * delta
		_face_direction(_walk_direction, delta)

		if _state_time_left <= 0.0:
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


func _stop_run_away(player: Node3D) -> void:
	if player != _detected_player:
		return

	_detected_player = null
	_resume_idle_or_run_away()


func _start_dash_damage(push_direction: Vector3) -> void:
	if push_direction == Vector3.ZERO:
		push_direction = global_transform.basis.z

	_detected_player = null
	_state = "dash_damage_push"
	_damage_state_time_left = dash_hit_push_duration
	_damage_push_direction = push_direction.normalized()
	_damage_push_elapsed = 0.0
	_damage_push_distance_ratio = 0.0
	_play_animation(damage_animation_name, true)


func _process_dash_damage_push(delta: float) -> void:
	if dash_hit_push_duration <= 0.0 or dash_hit_push_distance <= 0.0:
		_start_dash_damage_hold()
		return

	_damage_push_elapsed = minf(_damage_push_elapsed + delta, dash_hit_push_duration)
	var progress := _damage_push_elapsed / dash_hit_push_duration
	var slowdown_power := maxf(dash_hit_push_slowdown_power, 1.0)
	var distance_ratio := 1.0 - pow(1.0 - progress, slowdown_power)
	var frame_distance := (distance_ratio - _damage_push_distance_ratio) * dash_hit_push_distance

	global_position += _damage_push_direction * frame_distance
	_face_direction(_damage_push_direction, delta)
	_damage_push_distance_ratio = distance_ratio
	_damage_state_time_left -= delta

	if _damage_state_time_left <= 0.0:
		_start_dash_damage_hold()


func _start_dash_damage_hold() -> void:
	_state = "dash_damage_hold"
	_damage_state_time_left = dash_hit_damage_duration
	_damage_push_direction = Vector3.ZERO
	_damage_push_elapsed = 0.0
	_damage_push_distance_ratio = 0.0
	_play_animation(damage_animation_name, true)


func _process_dash_damage_hold(delta: float) -> void:
	_damage_state_time_left -= delta

	if _damage_state_time_left <= 0.0:
		_resume_idle_or_run_away()


func _resume_idle_or_run_away() -> void:
	var player := _find_detected_chicken()
	if player != null:
		_start_run_away(player)
	else:
		_start_idle()


func _start_idle() -> void:
	_state = "idle"
	_state_time_left = _rng.randf_range(idle_time_min, idle_time_max)
	_walk_direction = Vector3.ZERO
	_play_animation(idle_animation_name)


func _start_walk() -> void:
	_state = "walk"
	_state_time_left = _rng.randf_range(walk_time_min, walk_time_max)
	_walk_direction = _get_random_walk_direction()
	_play_animation(walk_animation_name)


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
	if _state == "dash_damage_push" or _state == "dash_damage_hold":
		return

	var player := _get_detected_chicken(body)
	if player != null:
		_start_run_away(player)


func _on_player_detection_body_exited(body: Node3D) -> void:
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


func take_damage(damage: int) -> void:
	_apply_damage(damage)


func take_dash_hit(direction: Vector3, damage: int) -> void:
	_apply_damage(damage)
	if health > 0:
		_start_dash_damage(direction)


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
	label.outline_size = 8
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
