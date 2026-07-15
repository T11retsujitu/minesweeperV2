extends Control

const FxConfig = preload("res://scripts/presentation/fx_config.gd")

var max_value = 1
var current_value = 0.0
var ghost_value = 0.0
var fill_color = Color.WHITE
var hp_tween = null
var flash_tween = null
var animation_token = 0

var title_label = null
var bar_background = null
var ghost_rect = null
var fill_rect = null
var value_label = null


func setup(title_text, next_max_value, next_fill_color):
	if title_label == null:
		_build_view()
	max_value = max(1, int(next_max_value))
	fill_color = next_fill_color
	title_label.text = title_text
	fill_rect.color = fill_color
	set_value_immediate(max_value)


func set_value_immediate(value):
	animation_token += 1
	_kill_hp_tween()
	current_value = float(value)
	ghost_value = current_value
	_apply_fill_width()
	_apply_ghost_width()
	_update_value_label()


func animate_to(value):
	var target_value = float(value)
	if hp_tween == null and is_equal_approx(current_value, target_value):
		return

	animation_token += 1
	var token = animation_token
	_kill_hp_tween()
	var start_value = current_value
	var start_ghost_value = ghost_value
	var total_wait = FxConfig.HP_TWEEN_SEC + 0.15

	hp_tween = create_tween()
	hp_tween.set_parallel(true)
	hp_tween.tween_method(Callable(self, "_set_fill_value"), start_value, target_value, FxConfig.HP_TWEEN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hp_tween.tween_method(Callable(self, "_set_ghost_value"), start_ghost_value, target_value, FxConfig.HP_TWEEN_SEC).set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# A reset may kill the visual tween; the timer still resumes this coroutine.
	await get_tree().create_timer(total_wait).timeout
	if token != animation_token:
		return
	hp_tween = null
	_set_fill_value(target_value)
	_set_ghost_value(target_value)


func flash():
	if flash_tween != null:
		flash_tween.kill()
		flash_tween = null
	fill_rect.modulate = FxConfig.COLOR_HP_FLASH
	flash_tween = create_tween()
	flash_tween.tween_property(fill_rect, "modulate", Color.WHITE, 0.16)
	flash_tween.finished.connect(_on_flash_finished)


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_refresh_layout()


func _build_view():
	custom_minimum_size = Vector2(0, 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color(0.82, 0.87, 0.88))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)

	bar_background = ColorRect.new()
	bar_background.color = FxConfig.COLOR_HP_BACKGROUND
	bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_background.clip_contents = true
	add_child(bar_background)

	ghost_rect = ColorRect.new()
	ghost_rect.color = FxConfig.COLOR_HP_GHOST
	ghost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_background.add_child(ghost_rect)

	fill_rect = ColorRect.new()
	fill_rect.color = fill_color
	fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_background.add_child(fill_rect)

	value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.98))
	value_label.add_theme_constant_override("outline_size", 2)
	value_label.add_theme_color_override("font_outline_color", Color.BLACK)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_background.add_child(value_label)

	_refresh_layout()


func _refresh_layout():
	if title_label == null:
		return
	var width = max(0.0, size.x)
	var title_height = 16.0
	var bar_height = 22.0
	title_label.position = Vector2.ZERO
	title_label.size = Vector2(width, title_height)
	bar_background.position = Vector2(0.0, 18.0)
	bar_background.size = Vector2(width, bar_height)
	ghost_rect.position = Vector2.ZERO
	fill_rect.position = Vector2.ZERO
	value_label.position = Vector2.ZERO
	value_label.size = bar_background.size
	_apply_fill_width()
	_apply_ghost_width()


func _set_fill_value(value):
	current_value = float(value)
	_apply_fill_width()
	_update_value_label()


func _set_ghost_value(value):
	ghost_value = float(value)
	_apply_ghost_width()


func _apply_fill_width():
	if fill_rect == null:
		return
	fill_rect.size = Vector2(_value_width(current_value), bar_background.size.y)


func _apply_ghost_width():
	if ghost_rect == null:
		return
	ghost_rect.size = Vector2(_value_width(ghost_value), bar_background.size.y)


func _value_width(value):
	var ratio = clamp(float(value) / float(max_value), 0.0, 1.0)
	return bar_background.size.x * ratio


func _update_value_label():
	if value_label == null:
		return
	value_label.text = "%d/%d" % [int(round(current_value)), max_value]


func _kill_hp_tween():
	if hp_tween != null:
		hp_tween.kill()
		hp_tween = null


func _on_flash_finished():
	flash_tween = null
