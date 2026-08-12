extends Control

@export var mouse_cursor_texture: Texture2D
@export var mouse_cursor_hotspot: Vector2 = Vector2.ZERO
@export var ground_cursor_scene: PackedScene
@export var ground_plane_y: float = 0.0
@export var ground_cursor_height_offset: float = 0.12
@export var hide_system_cursor: bool = true
@export var face_control_node_name: String = "hero_girl01"

@onready var game_over: Control = get_node_or_null("GameOver") as Control
@onready var time_label: Label = get_node_or_null("MarginContainer/HBoxContainer/timesicon/time") as Label
@onready var wave_number_label: Label = get_node_or_null("wave_number") as Label
@onready var enemy_number_label: Label = get_node_or_null("enemy_number") as Label

var _ground_cursor: Node3D
var _face_control_node: Node
var _is_system_cursor_hidden := false
var _elapsed_time := 0.0
var _displayed_second := -1
var _game_timer_is_running := true
var _enemy_wave_spawner: Node


func _ready() -> void:
	_update_time_label(true)
	_update_wave_name("Wave 1")
	_update_enemy_number(0)
	_connect_enemy_wave_spawner()
	if ground_cursor_scene != null:
		_spawn_ground_cursor.call_deferred()
		return

	if mouse_cursor_texture != null:
		Input.set_custom_mouse_cursor(mouse_cursor_texture, Input.CURSOR_ARROW, mouse_cursor_hotspot)


func _exit_tree() -> void:
	if _ground_cursor != null:
		_ground_cursor.queue_free()
		_ground_cursor = null

	if _is_system_cursor_hidden:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_update_game_timer(delta)
	_update_ground_cursor_position()


func show_game_over() -> void:
	_game_timer_is_running = false
	if game_over != null:
		game_over.visible = true


func hide_game_over() -> void:
	if game_over != null:
		game_over.visible = false


func reset_game_timer() -> void:
	_elapsed_time = 0.0
	_displayed_second = -1
	_game_timer_is_running = true
	_update_time_label(true)


func _update_game_timer(delta: float) -> void:
	if not _game_timer_is_running:
		return

	_elapsed_time += maxf(delta, 0.0)
	_update_time_label()


func _update_time_label(force_update: bool = false) -> void:
	if time_label == null:
		return

	var total_seconds := floori(_elapsed_time)
	if not force_update and total_seconds == _displayed_second:
		return

	_displayed_second = total_seconds
	var minutes := floori(float(total_seconds) / 60.0)
	var seconds := total_seconds % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]


func _connect_enemy_wave_spawner() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_enemy_wave_spawner = scene_root.get_node_or_null("EnemyWaveSpawner")
	if _enemy_wave_spawner == null:
		_enemy_wave_spawner = scene_root.find_child("EnemyWaveSpawner", true, false)
	if _enemy_wave_spawner == null or not _enemy_wave_spawner.has_signal("wave_started"):
		return

	var wave_started_callback := Callable(self, "_on_wave_started")
	if not _enemy_wave_spawner.is_connected("wave_started", wave_started_callback):
		_enemy_wave_spawner.connect("wave_started", wave_started_callback)
	var enemy_count_callback := Callable(self, "_on_active_enemy_count_changed")
	if _enemy_wave_spawner.has_signal("active_enemy_count_changed") and not _enemy_wave_spawner.is_connected("active_enemy_count_changed", enemy_count_callback):
		_enemy_wave_spawner.connect("active_enemy_count_changed", enemy_count_callback)
	if _enemy_wave_spawner.has_method("get_active_enemy_count"):
		_update_enemy_number(int(_enemy_wave_spawner.call("get_active_enemy_count")))


func _on_wave_started(_wave_index: int, wave_name: String) -> void:
	_update_wave_name(wave_name)


func _update_wave_name(wave_name: String) -> void:
	if wave_number_label != null:
		wave_number_label.text = wave_name


func _on_active_enemy_count_changed(enemy_count: int) -> void:
	_update_enemy_number(enemy_count)


func _update_enemy_number(enemy_count: int) -> void:
	if enemy_number_label != null:
		enemy_number_label.text = "enemy %d" % maxi(enemy_count, 0)


func _spawn_ground_cursor() -> void:
	_ground_cursor = ground_cursor_scene.instantiate() as Node3D
	if _ground_cursor == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		add_child(_ground_cursor)
	else:
		scene_root.add_child(_ground_cursor)

	_update_ground_cursor_position()


func _update_ground_cursor_position() -> void:
	if _ground_cursor == null:
		return

	if not _is_mouse_face_control_enabled():
		_ground_cursor.visible = false
		_hide_system_cursor()
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		_ground_cursor.visible = false
		_hide_system_cursor()
		return

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) <= 0.001:
		_ground_cursor.visible = false
		_hide_system_cursor()
		return

	var distance_to_plane: float = (ground_plane_y - ray_origin.y) / ray_direction.y
	if distance_to_plane <= 0.0:
		_ground_cursor.visible = false
		_hide_system_cursor()
		return

	var cursor_position: Vector3 = ray_origin + ray_direction * distance_to_plane
	cursor_position.y = ground_plane_y + ground_cursor_height_offset
	_ground_cursor.global_position = cursor_position
	_ground_cursor.visible = true
	_hide_system_cursor()


func _hide_system_cursor() -> void:
	if not hide_system_cursor:
		return
	if _is_system_cursor_hidden:
		return

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_is_system_cursor_hidden = true


func _show_system_cursor() -> void:
	if not _is_system_cursor_hidden:
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_is_system_cursor_hidden = false


func _is_mouse_face_control_enabled() -> bool:
	var face_control_node := _get_face_control_node()
	if face_control_node == null:
		return false
	if not face_control_node.has_method("is_mouse_face_control_enabled"):
		return false

	return bool(face_control_node.call("is_mouse_face_control_enabled"))


func _get_face_control_node() -> Node:
	if _face_control_node != null and is_instance_valid(_face_control_node):
		return _face_control_node

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return null

	_face_control_node = scene_root.find_child(face_control_node_name, true, false)
	return _face_control_node
