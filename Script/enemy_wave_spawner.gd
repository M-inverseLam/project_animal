extends Node

signal wave_started(wave_index: int, wave_name: String)
signal enemy_spawned(enemy: Node3D, wave_index: int, enemy_index: int)
signal wave_completed(wave_index: int, wave_name: String)
signal all_waves_completed

const WAVE_CONFIG_PATH := "res://Asset/enemywave/enemy_waves.json"
const SPAWN_PARENT_PATH := NodePath("..")

class SpawnEntry:
	var enemy_scene_path: String
	var spawn_time_offset: float
	var spawn_marker_path: NodePath


class WaveData:
	var wave_name: String
	var start_delay: float
	var wait_until_defeated: bool
	var enemy_list: Array[SpawnEntry] = []


var _auto_start := true
var _outside_camera_margin := 3.0
var _waves: Array[WaveData] = []
var _is_running := false
var _active_enemies: Array[Node3D] = []
var _enemy_scene_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if not _load_wave_config():
		return
	if _auto_start:
		start_waves.call_deferred()


func start_waves() -> void:
	if _is_running:
		return

	_is_running = true
	for wave_index in range(_waves.size()):
		if not _is_running:
			break

		var wave: WaveData = _waves[wave_index]
		if wave.start_delay > 0.0:
			await get_tree().create_timer(wave.start_delay).timeout
			if not _is_running:
				break

		await _run_wave(wave_index, wave)

	_is_running = false
	all_waves_completed.emit()


func stop_waves() -> void:
	_is_running = false


func _run_wave(wave_index: int, wave: WaveData) -> void:
	wave_started.emit(wave_index, wave.wave_name)
	var spawn_entries: Array[SpawnEntry] = wave.enemy_list.duplicate()
	spawn_entries.sort_custom(_sort_spawn_entries)
	var previous_offset := 0.0

	for enemy_index in range(spawn_entries.size()):
		if not _is_running:
			return

		var spawn_entry: SpawnEntry = spawn_entries[enemy_index]
		var spawn_offset := maxf(spawn_entry.spawn_time_offset, 0.0)
		var delay := maxf(spawn_offset - previous_offset, 0.0)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
			if not _is_running:
				return

		_spawn_enemy(spawn_entry, wave_index, enemy_index)
		previous_offset = spawn_offset

	if wave.wait_until_defeated:
		while _is_running and _has_active_enemies():
			await get_tree().process_frame

	if _is_running:
		wave_completed.emit(wave_index, wave.wave_name)


func _spawn_enemy(spawn_entry: SpawnEntry, wave_index: int, enemy_index: int) -> void:
	var enemy_scene := _get_enemy_scene(spawn_entry.enemy_scene_path)
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate() as Node3D
	if enemy == null:
		push_warning("Enemy scene root must inherit Node3D: " + spawn_entry.enemy_scene_path)
		return

	var spawn_parent := get_node_or_null(SPAWN_PARENT_PATH)
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene
	if spawn_parent == null:
		enemy.free()
		return

	var spawn_height := _get_enemy_spawn_height(enemy)
	var spawn_transform := Transform3D(Basis.IDENTITY, _get_random_offscreen_position(spawn_height))
	if not spawn_entry.spawn_marker_path.is_empty():
		var spawn_marker := get_node_or_null(spawn_entry.spawn_marker_path) as Node3D
		if spawn_marker != null:
			spawn_transform = spawn_marker.global_transform
		else:
			push_warning("Enemy spawn marker not found: " + String(spawn_entry.spawn_marker_path))

	spawn_parent.add_child(enemy, true)
	enemy.global_transform = spawn_transform
	_active_enemies.append(enemy)
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy), CONNECT_ONE_SHOT)
	enemy_spawned.emit(enemy, wave_index, enemy_index)


func _load_wave_config() -> bool:
	_waves.clear()
	_enemy_scene_cache.clear()
	if not FileAccess.file_exists(WAVE_CONFIG_PATH):
		push_error("Enemy wave file not found: " + WAVE_CONFIG_PATH)
		return false

	var file := FileAccess.open(WAVE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open enemy wave file: " + WAVE_CONFIG_PATH)
		return false

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_error(
			"Enemy wave JSON error at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false

	var root_value: Variant = json.data
	if not root_value is Dictionary:
		push_error("Enemy wave file root must be a JSON object.")
		return false

	var root_data: Dictionary = root_value
	_auto_start = bool(root_data.get("auto_start", true))
	_outside_camera_margin = maxf(float(root_data.get("outside_camera_margin", 3.0)), 0.0)
	var raw_waves_value: Variant = root_data.get("waves", [])
	if not raw_waves_value is Array:
		push_error("Enemy wave file 'waves' must be an array.")
		return false

	var raw_waves: Array = raw_waves_value
	for wave_index in range(raw_waves.size()):
		var raw_wave_value: Variant = raw_waves[wave_index]
		if not raw_wave_value is Dictionary:
			push_warning("Skipping invalid wave at index %d." % wave_index)
			continue

		var raw_wave: Dictionary = raw_wave_value
		var wave := WaveData.new()
		wave.wave_name = String(raw_wave.get("name", "Wave %d" % (wave_index + 1)))
		wave.start_delay = maxf(float(raw_wave.get("start_delay", 0.0)), 0.0)
		wave.wait_until_defeated = bool(raw_wave.get("wait_until_defeated", true))
		_load_enemy_list(wave, raw_wave, wave_index)
		_waves.append(wave)

	return true


func _load_enemy_list(wave: WaveData, raw_wave: Dictionary, wave_index: int) -> void:
	var raw_enemies_value: Variant = raw_wave.get("enemies", [])
	if not raw_enemies_value is Array:
		push_warning("Wave %d 'enemies' must be an array." % (wave_index + 1))
		return

	var raw_enemies: Array = raw_enemies_value
	var previous_group_last_spawn_offset := 0.0
	for enemy_index in range(raw_enemies.size()):
		var raw_enemy_value: Variant = raw_enemies[enemy_index]
		if not raw_enemy_value is Dictionary:
			push_warning("Skipping invalid enemy %d in wave %d." % [enemy_index, wave_index])
			continue

		var raw_enemy: Dictionary = raw_enemy_value
		var scene_path := String(raw_enemy.get("scene", ""))
		if scene_path.is_empty():
			push_warning("Skipping enemy with no scene path in wave %d." % (wave_index + 1))
			continue

		var quantity := maxi(int(raw_enemy.get("quantity", 1)), 1)
		var first_spawn_offset := maxf(float(raw_enemy.get("spawn_time_offset", 0.0)), 0.0)
		var spawn_interval := maxf(float(raw_enemy.get("spawn_interval", 0.0)), 0.0)
		var spawn_after_previous_group := bool(raw_enemy.get("spawn_after_previous_group", false))
		if spawn_after_previous_group:
			var spawn_delay := maxf(float(raw_enemy.get("spawn_delay", 0.0)), 0.0)
			first_spawn_offset = previous_group_last_spawn_offset + spawn_delay
		var spawn_marker_path := NodePath(String(raw_enemy.get("spawn_marker_path", "")))
		for quantity_index in range(quantity):
			var spawn_entry := SpawnEntry.new()
			spawn_entry.enemy_scene_path = scene_path
			spawn_entry.spawn_time_offset = first_spawn_offset + spawn_interval * quantity_index
			spawn_entry.spawn_marker_path = spawn_marker_path
			wave.enemy_list.append(spawn_entry)

		previous_group_last_spawn_offset = first_spawn_offset + spawn_interval * (quantity - 1)


func _get_enemy_scene(scene_path: String) -> PackedScene:
	if _enemy_scene_cache.has(scene_path):
		return _enemy_scene_cache[scene_path] as PackedScene

	var resource := load(scene_path)
	var enemy_scene := resource as PackedScene
	if enemy_scene == null:
		push_warning("Could not load enemy scene: " + scene_path)
		return null

	_enemy_scene_cache[scene_path] = enemy_scene
	return enemy_scene


func _has_active_enemies() -> bool:
	for index in range(_active_enemies.size() - 1, -1, -1):
		if not is_instance_valid(_active_enemies[index]):
			_active_enemies.remove_at(index)

	return not _active_enemies.is_empty()


func _on_enemy_tree_exited(enemy: Node3D) -> void:
	_active_enemies.erase(enemy)


func _sort_spawn_entries(first: SpawnEntry, second: SpawnEntry) -> bool:
	return first.spawn_time_offset < second.spawn_time_offset


func _get_enemy_spawn_height(enemy: Node3D) -> float:
	for property in enemy.get_property_list():
		if property.get("name", "") == "spawn_height":
			var height_value: Variant = enemy.get("spawn_height")
			if height_value is float or height_value is int:
				return float(height_value)
			break

	return 0.0


func _get_random_offscreen_position(spawn_height: float) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _get_fallback_offscreen_position(spawn_height)

	var viewport_size := get_viewport().get_visible_rect().size
	var screen_corners := PackedVector2Array([
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		viewport_size,
		Vector2(0.0, viewport_size.y),
	])
	var ground_corners: Array[Vector3] = []
	for screen_corner in screen_corners:
		var ray_origin := camera.project_ray_origin(screen_corner)
		var ray_direction := camera.project_ray_normal(screen_corner)
		if absf(ray_direction.y) <= 0.001:
			return _get_fallback_offscreen_position(spawn_height)

		var distance_to_plane := (spawn_height - ray_origin.y) / ray_direction.y
		if distance_to_plane <= 0.0:
			return _get_fallback_offscreen_position(spawn_height)

		ground_corners.append(ray_origin + ray_direction * distance_to_plane)

	var edge_index := _rng.randi_range(0, ground_corners.size() - 1)
	var edge_start := ground_corners[edge_index]
	var edge_end := ground_corners[(edge_index + 1) % ground_corners.size()]
	var spawn_position := edge_start.lerp(edge_end, _rng.randf())
	var view_center := Vector3.ZERO
	for corner in ground_corners:
		view_center += corner
	view_center /= float(ground_corners.size())

	var outward_direction := spawn_position - view_center
	outward_direction.y = 0.0
	if outward_direction != Vector3.ZERO:
		spawn_position += outward_direction.normalized() * _outside_camera_margin
	spawn_position.y = spawn_height
	return spawn_position


func _get_fallback_offscreen_position(spawn_height: float) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var center := Vector3.ZERO
	if camera != null:
		center = camera.global_position
	center.y = spawn_height

	var angle := _rng.randf_range(0.0, TAU)
	var direction := Vector3(sin(angle), 0.0, cos(angle))
	return center + direction * (30.0 + _outside_camera_margin)
