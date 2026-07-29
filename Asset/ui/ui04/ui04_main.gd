extends Control

@export var mouse_cursor_texture: Texture2D
@export var mouse_cursor_hotspot: Vector2 = Vector2.ZERO
@export var ground_cursor_scene: PackedScene
@export var ground_plane_y: float = 0.0
@export var ground_cursor_height_offset: float = 0.12
@export var hide_system_cursor: bool = true
@export var face_control_node_name: String = "hero_girl01"

@onready var game_over: Control = get_node_or_null("GameOver") as Control

var _ground_cursor: Node3D
var _face_control_node: Node
var _is_system_cursor_hidden := false


func _ready() -> void:
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


func _process(_delta: float) -> void:
	_update_ground_cursor_position()


func show_game_over() -> void:
	if game_over != null:
		game_over.visible = true


func hide_game_over() -> void:
	if game_over != null:
		game_over.visible = false


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
