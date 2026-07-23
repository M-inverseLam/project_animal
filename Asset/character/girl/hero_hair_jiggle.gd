extends SkeletonModifier3D

@export var enabled: bool = true
@export var hair_bones := PackedStringArray(["hairtail1", "hairtail2"])
@export var movement_jiggle_strength: float = 1.5
@export var idle_jiggle_strength: float = 0.0
@export var jiggle_speed: float = 8.0
@export var follow_smoothing: float = 10.0

var _skeleton: Skeleton3D
var _bone_ids: Array[int] = []
var _last_skeleton_position := Vector3.ZERO
var _smoothed_local_motion := Vector3.ZERO
var _time := 0.0


func _ready() -> void:
	_cache_skeleton()


func _skeleton_changed(_old_skeleton: Skeleton3D, new_skeleton: Skeleton3D) -> void:
	_skeleton = new_skeleton
	_cache_bones()
	if _skeleton != null:
		_last_skeleton_position = _skeleton.global_position


func _validate_bone_names() -> void:
	_cache_bones()


func _process_modification_with_delta(delta: float) -> void:
	if not enabled:
		return
	if delta <= 0.0:
		return
	if _skeleton == null:
		_cache_skeleton()
	if _skeleton == null:
		return
	if _bone_ids.is_empty():
		_cache_bones()
	if _bone_ids.is_empty():
		return

	_time += delta
	var world_motion := (_skeleton.global_position - _last_skeleton_position) / delta
	_last_skeleton_position = _skeleton.global_position

	var local_motion := _skeleton.global_basis.inverse() * world_motion
	local_motion.y = 0.0
	_smoothed_local_motion = _smoothed_local_motion.lerp(local_motion, clampf(delta * follow_smoothing, 0.0, 1.0))

	for i in range(_bone_ids.size()):
		var bone_id := _bone_ids[i]
		var weight := 1.0 - float(i) * 0.2
		var side_sway := sin(_time * jiggle_speed + float(i) * 0.9) * idle_jiggle_strength
		var back_sway := clampf(_smoothed_local_motion.z * 0.03, -movement_jiggle_strength, movement_jiggle_strength)
		var x_sway := clampf(-_smoothed_local_motion.x * 0.03, -movement_jiggle_strength, movement_jiggle_strength)
		var additive_rotation := Quaternion(Vector3.RIGHT, back_sway * weight) * Quaternion(Vector3.FORWARD, (side_sway + x_sway) * weight)

		_skeleton.set_bone_pose_rotation(bone_id, _skeleton.get_bone_pose_rotation(bone_id) * additive_rotation)


func _cache_skeleton() -> void:
	_skeleton = get_skeleton()
	if _skeleton == null:
		_skeleton = get_parent() as Skeleton3D
	_cache_bones()
	if _skeleton != null:
		_last_skeleton_position = _skeleton.global_position


func _cache_bones() -> void:
	_bone_ids.clear()
	if _skeleton == null:
		return

	for bone_name in hair_bones:
		var bone_id := _skeleton.find_bone(bone_name)
		if bone_id != -1:
			_bone_ids.append(bone_id)
