@tool
extends EditorInspectorPlugin

const ENEMY_AI_SCRIPT := "res://Script/enemy_Ai01.gd"


func _can_handle(object: Object) -> bool:
	if not (object is Node):
		return false

	var script := object.get_script() as Script
	return script != null and script.resource_path == ENEMY_AI_SCRIPT


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if name == "idle_time_range" or name == "walk_time_range" or name == "chase_time_range" or name == "shoot_time_range":
		add_property_editor(name, TimeRangeEditor.new())
		return true

	return false


class TimeRangeEditor:
	extends EditorProperty

	var _min_edit := LineEdit.new()
	var _max_edit := LineEdit.new()
	var _updating := false


	func _init() -> void:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_make_label("Min"))
		row.add_child(_min_edit)
		row.add_child(_make_label("Max"))
		row.add_child(_max_edit)
		add_child(row)

		_setup_number_edit(_min_edit)
		_setup_number_edit(_max_edit)
		add_focusable(_min_edit)
		add_focusable(_max_edit)

		_min_edit.text_submitted.connect(_on_text_submitted)
		_max_edit.text_submitted.connect(_on_text_submitted)
		_min_edit.focus_exited.connect(_on_focus_exited)
		_max_edit.focus_exited.connect(_on_focus_exited)


	func _make_label(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size.x = 30.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return label


	func _setup_number_edit(line_edit: LineEdit) -> void:
		line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line_edit.placeholder_text = "0.0"


	func _update_property() -> void:
		var edited_object := get_edited_object()
		if edited_object == null:
			return

		var value: Vector2 = edited_object.get(get_edited_property())
		_updating = true
		_min_edit.text = _format_float(value.x)
		_max_edit.text = _format_float(value.y)
		_updating = false


	func _on_text_submitted(_text: String) -> void:
		_emit_range()


	func _on_focus_exited() -> void:
		_emit_range()


	func _emit_range() -> void:
		if _updating:
			return

		var min_value := _min_edit.text.to_float()
		var max_value := _max_edit.text.to_float()
		emit_changed(get_edited_property(), Vector2(min_value, max_value))


	func _format_float(value: float) -> String:
		return str(snappedf(value, 0.001))
