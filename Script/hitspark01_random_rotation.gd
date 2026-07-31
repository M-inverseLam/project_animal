extends Node3D

func _ready() -> void:
	_align_to_camera()


func _align_to_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	global_basis = camera.global_basis
