extends Node3D

const HORIZONTAL_TILE_RADIUS := 2
const VERTICAL_TILE_RADIUS := 1
const GRID_TILE_COUNT := (HORIZONTAL_TILE_RADIUS * 2 + 1) * (VERTICAL_TILE_RADIUS * 2 + 1)
const DECAL_SCENES: Array[PackedScene] = [
	preload("res://Asset/stage/forest/forest_ground_decal01.tscn"),
	preload("res://Asset/stage/forest/forest_ground_decal02.tscn"),
	preload("res://Asset/stage/forest/forest_ground_decal03.tscn"),
	preload("res://Asset/stage/forest/forest_ground_decal04.tscn"),
	preload("res://Asset/stage/forest/forest_ground_decal05.tscn"),
	preload("res://Asset/stage/forest/forest_ground_decal06.tscn"),
]
const DECAL_SIZES: Array[Vector2] = [
	Vector2(20.0, 20.0),
	Vector2(20.0, 20.0),
	Vector2(20.0, 20.0),
	Vector2(10.0, 10.0),
	Vector2(10.0, 10.0),
	Vector2(10.0, 10.0),
]

@export var tile_size := Vector2(20.0, 30.0)
@export var camera_path: NodePath

@export_group("Ground Decals")
@export_range(0.0, 1.0, 0.05) var decal_spawn_chance: float = 1.0
@export_range(0.001, 1.0, 0.001, "suffix:m") var decal_height: float = 0.03
@export_range(0.0, 5.0, 0.1, "suffix:m") var decal_edge_padding: float = 0.25
@export var decal_seed: int = 1337

@onready var tile_template := get_node_or_null("MeshInstance3D") as MeshInstance3D

var _camera: Camera3D
var _tiles: Array[MeshInstance3D] = []
var _decals: Array[Node3D] = []
var _center_cell := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
	_create_tile_grid()
	_update_tile_positions(true)


func _process(_delta: float) -> void:
	_update_tile_positions()


func _create_tile_grid() -> void:
	if tile_template == null:
		return

	_tiles.append(tile_template)
	for tile_index in range(1, GRID_TILE_COUNT):
		var tile := tile_template.duplicate() as MeshInstance3D
		if tile == null:
			continue
		tile.name = "GroundTile%02d" % (tile_index + 1)
		add_child(tile)
		_tiles.append(tile)

	_decals.resize(GRID_TILE_COUNT)


func _update_tile_positions(force_update: bool = false) -> void:
	if _tiles.size() != GRID_TILE_COUNT or tile_size.x <= 0.0 or tile_size.y <= 0.0:
		return

	var camera := _get_camera()
	if camera == null:
		return

	var ground_bounds := _get_camera_ground_bounds(camera)
	var bounds_center := ground_bounds.get_center()
	var next_center_cell := _center_cell
	if _center_cell.x == 2147483647:
		next_center_cell = Vector2i(
			roundi(bounds_center.x / tile_size.x),
			roundi(bounds_center.y / tile_size.y)
		)
	next_center_cell.x = _fit_grid_axis_to_bounds(
		next_center_cell.x,
		ground_bounds.position.x,
		ground_bounds.end.x,
		tile_size.x,
		float(HORIZONTAL_TILE_RADIUS) + 0.5
	)
	next_center_cell.y = _fit_grid_axis_to_bounds(
		next_center_cell.y,
		ground_bounds.position.y,
		ground_bounds.end.y,
		tile_size.y,
		float(VERTICAL_TILE_RADIUS) + 0.5
	)
	if not force_update and next_center_cell == _center_cell:
		return

	_center_cell = next_center_cell
	var tile_index := 0
	for z_offset in range(-VERTICAL_TILE_RADIUS, VERTICAL_TILE_RADIUS + 1):
		for x_offset in range(-HORIZONTAL_TILE_RADIUS, HORIZONTAL_TILE_RADIUS + 1):
			var tile_cell := Vector2i(_center_cell.x + x_offset, _center_cell.y + z_offset)
			_tiles[tile_index].position = Vector3(
				float(tile_cell.x) * tile_size.x,
				0.0,
				float(tile_cell.y) * tile_size.y
			)
			_update_tile_decal(tile_index, tile_cell)
			tile_index += 1


func _update_tile_decal(tile_index: int, tile_cell: Vector2i) -> void:
	if _decals[tile_index] != null:
		_decals[tile_index].free()
		_decals[tile_index] = null

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(tile_cell.x, tile_cell.y, decal_seed))
	if rng.randf() > decal_spawn_chance:
		return

	var decal_index := rng.randi_range(0, DECAL_SCENES.size() - 1)
	var decal := DECAL_SCENES[decal_index].instantiate() as Node3D
	if decal == null:
		return

	var decal_size := DECAL_SIZES[decal_index]
	var maximum_x_offset := maxf((tile_size.x - decal_size.x) * 0.5 - decal_edge_padding, 0.0)
	var maximum_z_offset := maxf((tile_size.y - decal_size.y) * 0.5 - decal_edge_padding, 0.0)
	var tile_center := Vector3(float(tile_cell.x) * tile_size.x, decal_height, float(tile_cell.y) * tile_size.y)
	decal.position = tile_center + Vector3(
		rng.randf_range(-maximum_x_offset, maximum_x_offset),
		0.0,
		rng.randf_range(-maximum_z_offset, maximum_z_offset)
	)
	decal.rotation.y = float(rng.randi_range(0, 3)) * PI * 0.5
	decal.name = "GroundDecal%02d" % (tile_index + 1)
	_disable_decal_shadows(decal)
	add_child(decal)
	_decals[tile_index] = decal


func _disable_decal_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_decal_shadows(child)


func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	_camera = get_viewport().get_camera_3d()
	return _camera


func _fit_grid_axis_to_bounds(
	current_cell: int,
	minimum: float,
	maximum: float,
	axis_tile_size: float,
	coverage_radius: float
) -> int:
	var minimum_valid_cell := ceili(maximum / axis_tile_size - coverage_radius)
	var maximum_valid_cell := floori(minimum / axis_tile_size + coverage_radius)
	if minimum_valid_cell <= maximum_valid_cell:
		return clampi(current_cell, minimum_valid_cell, maximum_valid_cell)

	return roundi(((minimum + maximum) * 0.5) / axis_tile_size)


func _get_camera_ground_bounds(camera: Camera3D) -> Rect2:
	var ground_height := global_position.y
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		var fallback_focus := to_local(_get_forward_ground_focus(camera, ground_height))
		return Rect2(Vector2(fallback_focus.x, fallback_focus.z), Vector2.ZERO)

	var screen_corners := PackedVector2Array([
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		viewport_size,
		Vector2(0.0, viewport_size.y),
	])
	var minimum_x := INF
	var maximum_x := -INF
	var minimum_z := INF
	var maximum_z := -INF
	var intersection_count := 0
	var ground_plane := Plane(Vector3.UP, ground_height)

	for screen_corner in screen_corners:
		var ray_origin := camera.project_ray_origin(screen_corner)
		var ray_direction := camera.project_ray_normal(screen_corner)
		var intersection: Variant = ground_plane.intersects_ray(ray_origin, ray_direction)
		if not intersection is Vector3:
			continue

		var ground_point := to_local(intersection as Vector3)
		minimum_x = minf(minimum_x, ground_point.x)
		maximum_x = maxf(maximum_x, ground_point.x)
		minimum_z = minf(minimum_z, ground_point.z)
		maximum_z = maxf(maximum_z, ground_point.z)
		intersection_count += 1

	if intersection_count == 0:
		var fallback_focus := to_local(_get_forward_ground_focus(camera, ground_height))
		return Rect2(Vector2(fallback_focus.x, fallback_focus.z), Vector2.ZERO)
	return Rect2(
		Vector2(minimum_x, minimum_z),
		Vector2(maximum_x - minimum_x, maximum_z - minimum_z)
	)


func _get_forward_ground_focus(camera: Camera3D, ground_height: float) -> Vector3:
	var ray_origin := camera.global_position
	var ray_direction := -camera.global_transform.basis.z.normalized()
	if absf(ray_direction.y) <= 0.0001:
		return Vector3(ray_origin.x, ground_height, ray_origin.z)

	var intersection_distance := (ground_height - ray_origin.y) / ray_direction.y
	if intersection_distance < 0.0:
		return Vector3(ray_origin.x, ground_height, ray_origin.z)
	return ray_origin + ray_direction * intersection_distance
