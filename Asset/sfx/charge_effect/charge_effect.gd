extends Node3D

@export_group("Fade")
@export var fade_in_duration: float = 0.2
@export var fade_out_duration: float = 0.2

var _materials: Array[ShaderMaterial] = []
var _fade_tween: Tween
var _current_alpha := 1.0


func _ready() -> void:
	_collect_unique_shader_materials(self)
	_current_alpha = 0.0
	_set_alpha(_current_alpha)

	if fade_in_duration <= 0.0:
		_set_alpha(1.0)
		return

	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_alpha, 0.0, 1.0, fade_in_duration)


func fade_out_and_free() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	if fade_out_duration <= 0.0:
		queue_free()
		return

	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_alpha, _current_alpha, 0.0, fade_out_duration)
	_fade_tween.tween_callback(queue_free)


func _set_alpha(value: float) -> void:
	_current_alpha = clampf(value, 0.0, 1.0)
	for material in _materials:
		material.set_shader_parameter("alpha_multiplier", _current_alpha)


func _collect_unique_shader_materials(node: Node) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material: Material = mesh_instance.get_active_material(surface_index)
			var shader_material := source_material as ShaderMaterial
			if shader_material == null:
				continue

			var unique_material := shader_material.duplicate() as ShaderMaterial
			if unique_material == null:
				continue

			mesh_instance.set_surface_override_material(surface_index, unique_material)
			_materials.append(unique_material)

	for child in node.get_children():
		_collect_unique_shader_materials(child)
