extends Node

signal wave_started(wave_index: int, wave_name: String)
signal enemy_spawned(enemy: Node3D, wave_index: int, enemy_index: int)
signal active_enemy_count_changed(enemy_count: int)
signal wave_completed(wave_index: int, wave_name: String)
signal all_waves_completed

const WAVE_CONFIG_PATH := "res://Asset/enemywave/enemy_wave_forest.csv"
const SPAWN_PARENT_PATH := NodePath("..")
const SPAWN_AREA_NAME := "spawnArea"
const SPAWN_POSITION_ATTEMPTS := 64

class SpawnEntry:
	var enemy_scene_path: String
	var spawn_time_offset: float


class WaveData:
	var wave_name: String
	var start_delay: float
	var wait_until_defeated: bool
	var enemy_list: Array[SpawnEntry] = []


var _auto_start := true
var _outside_camera_margin_pixels := 80.0
var _waves: Array[WaveData] = []
var _is_running := false
var _active_enemies: Array[Node3D] = []
var _enemy_scene_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _spawn_area: Area3D
var _spawn_area_shape: CollisionShape3D
var _wave_sequence_started_at_msec := 0


func _ready() -> void:
	_rng.randomize()
	if not _load_wave_config():
		return
	if not _cache_spawn_area():
		return
	if _auto_start:
		start_waves.call_deferred()


func start_waves() -> void:
	if _is_running:
		return

	_is_running = true
	_wave_sequence_started_at_msec = Time.get_ticks_msec()
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
	var spawn_entries: Array[SpawnEntry] = wave.enemy_list.duplicate()
	spawn_entries.sort_custom(_sort_spawn_entries)
	var wave_has_started := false

	for enemy_index in range(spawn_entries.size()):
		if not _is_running:
			return

		var spawn_entry: SpawnEntry = spawn_entries[enemy_index]
		var spawn_offset := maxf(spawn_entry.spawn_time_offset, 0.0)
		var elapsed := float(Time.get_ticks_msec() - _wave_sequence_started_at_msec) / 1000.0
		var delay := maxf(spawn_offset - elapsed, 0.0)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
			if not _is_running:
				return

		if not wave_has_started:
			wave_has_started = true
			wave_started.emit(wave_index, wave.wave_name)
		_spawn_enemy(spawn_entry, wave_index, enemy_index)

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
	var spawn_transform := Transform3D(Basis.IDENTITY, _get_random_spawn_area_position(spawn_height))

	spawn_parent.add_child(enemy, true)
	enemy.global_transform = spawn_transform
	_active_enemies.append(enemy)
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy), CONNECT_ONE_SHOT)
	active_enemy_count_changed.emit(_active_enemies.size())
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

	if file.eof_reached():
		push_error("Enemy wave CSV is empty: " + WAVE_CONFIG_PATH)
		return false

	var headers := file.get_csv_line()
	var column_indexes := _get_csv_column_indexes(headers)
	var required_columns := PackedStringArray([
		"wave",
		"name",
		"start_delay",
		"wait_until_defeated",
		"enemy_scene",
		"quantity",
		"spawn_time_offset",
		"spawn_interval",
		"spawn_after_previous_group",
		"spawn_delay",
	])
	for column_name in required_columns:
		if not column_indexes.has(column_name):
			push_error("Enemy wave CSV is missing column: " + column_name)
			return false

	var waves_by_id: Dictionary = {}
	var enemy_groups_by_wave: Dictionary = {}
	var row_number := 1
	while not file.eof_reached():
		var row := file.get_csv_line()
		row_number += 1
		if row.is_empty() or _csv_row_is_empty(row):
			continue

		var wave_id := _get_csv_value(row, column_indexes, "wave")
		if wave_id.is_empty():
			push_warning("Skipping enemy wave CSV row %d with no wave value." % row_number)
			continue

		if not waves_by_id.has(wave_id):
			var wave := WaveData.new()
			wave.wave_name = _get_csv_value(row, column_indexes, "name", "Wave " + wave_id)
			wave.start_delay = maxf(_get_csv_float(row, column_indexes, "start_delay"), 0.0)
			wave.wait_until_defeated = _get_csv_bool(row, column_indexes, "wait_until_defeated", true)
			waves_by_id[wave_id] = wave
			enemy_groups_by_wave[wave_id] = []
			_waves.append(wave)

		var scene_path := _get_csv_value(row, column_indexes, "enemy_scene")
		if scene_path.is_empty():
			push_warning("Skipping enemy wave CSV row %d with no enemy scene." % row_number)
			continue

		var enemy_group := {
			"scene": scene_path,
			"quantity": maxi(_get_csv_int(row, column_indexes, "quantity", 1), 1),
			"spawn_time_offset": maxf(_get_csv_float(row, column_indexes, "spawn_time_offset"), 0.0),
			"spawn_interval": maxf(_get_csv_float(row, column_indexes, "spawn_interval"), 0.0),
			"spawn_after_previous_group": _get_csv_bool(row, column_indexes, "spawn_after_previous_group", false),
			"spawn_delay": maxf(_get_csv_float(row, column_indexes, "spawn_delay"), 0.0),
		}
		(enemy_groups_by_wave[wave_id] as Array).append(enemy_group)

		var auto_start_value := _get_csv_value(row, column_indexes, "auto_start")
		if not auto_start_value.is_empty():
			_auto_start = _parse_csv_bool(auto_start_value, true)
		var margin_value := _get_csv_value(row, column_indexes, "outside_camera_margin_pixels")
		if not margin_value.is_empty():
			_outside_camera_margin_pixels = maxf(margin_value.to_float(), 0.0)

	for wave_id in waves_by_id:
		_load_enemy_groups(waves_by_id[wave_id] as WaveData, enemy_groups_by_wave[wave_id] as Array)

	if _waves.is_empty():
		push_error("Enemy wave CSV contains no valid waves.")
		return false

	return true


func _load_enemy_groups(wave: WaveData, raw_enemies: Array) -> void:
	var previous_group_last_spawn_offset := 0.0
	for raw_enemy_value in raw_enemies:
		var raw_enemy: Dictionary = raw_enemy_value as Dictionary
		var scene_path := String(raw_enemy.get("scene", ""))
		var quantity := maxi(int(raw_enemy.get("quantity", 1)), 1)
		var first_spawn_offset := maxf(float(raw_enemy.get("spawn_time_offset", 0.0)), 0.0)
		var spawn_interval := maxf(float(raw_enemy.get("spawn_interval", 0.0)), 0.0)
		var spawn_after_previous_group := bool(raw_enemy.get("spawn_after_previous_group", false))
		if spawn_after_previous_group:
			var spawn_delay := maxf(float(raw_enemy.get("spawn_delay", 0.0)), 0.0)
			first_spawn_offset = previous_group_last_spawn_offset + spawn_delay
		for quantity_index in range(quantity):
			var spawn_entry := SpawnEntry.new()
			spawn_entry.enemy_scene_path = scene_path
			spawn_entry.spawn_time_offset = first_spawn_offset + spawn_interval * quantity_index
			wave.enemy_list.append(spawn_entry)

		previous_group_last_spawn_offset = first_spawn_offset + spawn_interval * (quantity - 1)


func _get_csv_column_indexes(headers: PackedStringArray) -> Dictionary:
	var column_indexes := {}
	for index in range(headers.size()):
		var column_name := headers[index].strip_edges().to_lower().replace(" ", "_")
		if not column_name.is_empty():
			column_indexes[column_name] = index
	return column_indexes


func _get_csv_value(
	row: PackedStringArray,
	column_indexes: Dictionary,
	column_name: String,
	fallback: String = ""
) -> String:
	if not column_indexes.has(column_name):
		return fallback
	var column_index := int(column_indexes[column_name])
	if column_index < 0 or column_index >= row.size():
		return fallback
	var value := row[column_index].strip_edges()
	return fallback if value.is_empty() else value


func _get_csv_float(
	row: PackedStringArray,
	column_indexes: Dictionary,
	column_name: String,
	fallback: float = 0.0
) -> float:
	var value := _get_csv_value(row, column_indexes, column_name)
	return fallback if value.is_empty() else value.to_float()


func _get_csv_int(
	row: PackedStringArray,
	column_indexes: Dictionary,
	column_name: String,
	fallback: int = 0
) -> int:
	var value := _get_csv_value(row, column_indexes, column_name)
	return fallback if value.is_empty() else value.to_int()


func _get_csv_bool(
	row: PackedStringArray,
	column_indexes: Dictionary,
	column_name: String,
	fallback: bool
) -> bool:
	var value := _get_csv_value(row, column_indexes, column_name)
	return fallback if value.is_empty() else _parse_csv_bool(value, fallback)


func _parse_csv_bool(value: String, fallback: bool) -> bool:
	match value.strip_edges().to_lower():
		"true", "yes", "1", "on":
			return true
		"false", "no", "0", "off":
			return false
	return fallback


func _csv_row_is_empty(row: PackedStringArray) -> bool:
	for value in row:
		if not value.strip_edges().is_empty():
			return false
	return true


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
	active_enemy_count_changed.emit(_active_enemies.size())


func get_active_enemy_count() -> int:
	_has_active_enemies()
	return _active_enemies.size()


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


func _cache_spawn_area() -> bool:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		push_error("Enemy wave spawner could not find the current scene.")
		return false

	_spawn_area = scene_root.find_child(SPAWN_AREA_NAME, true, false) as Area3D
	if _spawn_area == null:
		push_error("Enemy spawn area not found: " + SPAWN_AREA_NAME)
		return false

	_spawn_area_shape = _spawn_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if _spawn_area_shape == null or not _spawn_area_shape.shape is BoxShape3D:
		push_error("Enemy spawn area requires a BoxShape3D CollisionShape3D.")
		return false

	return true


func _get_random_spawn_area_position(spawn_height: float) -> Vector3:
	var fallback_position := Vector3.ZERO
	for attempt in range(SPAWN_POSITION_ATTEMPTS):
		var candidate := _get_random_position_inside_spawn_area(spawn_height)
		fallback_position = candidate
		if _is_outside_camera_view(candidate):
			return candidate

	push_warning("Could not find an offscreen position inside " + SPAWN_AREA_NAME + ".")
	return fallback_position


func _get_random_position_inside_spawn_area(spawn_height: float) -> Vector3:
	var box_shape := _spawn_area_shape.shape as BoxShape3D
	var half_size := box_shape.size * 0.5
	var local_position := Vector3(
		_rng.randf_range(-half_size.x, half_size.x),
		0.0,
		_rng.randf_range(-half_size.z, half_size.z)
	)
	var spawn_position := _spawn_area_shape.global_transform * local_position
	spawn_position.y = _spawn_area.global_position.y + spawn_height
	return spawn_position


func _is_outside_camera_view(world_position: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(world_position):
		return true

	var viewport_size := get_viewport().get_visible_rect().size
	var screen_position := camera.unproject_position(world_position)
	return (
		screen_position.x < -_outside_camera_margin_pixels
		or screen_position.y < -_outside_camera_margin_pixels
		or screen_position.x > viewport_size.x + _outside_camera_margin_pixels
		or screen_position.y > viewport_size.y + _outside_camera_margin_pixels
	)
