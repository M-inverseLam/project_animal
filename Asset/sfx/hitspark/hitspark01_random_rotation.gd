extends Node3D

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_align_to_camera()
	rotate_object_local(Vector3.FORWARD, _rng.randf_range(0.0, TAU))


func _align_to_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	global_basis = camera.global_basis
