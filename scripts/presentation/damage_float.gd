extends Label

const FxConfig = preload("res://scripts/presentation/fx_config.gd")


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", FxConfig.FLOAT_FONT_SIZE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - FxConfig.FLOAT_RISE_PX, FxConfig.FLOAT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FxConfig.FLOAT_DURATION * 0.5).set_delay(FxConfig.FLOAT_DURATION * 0.5)
	tween.finished.connect(queue_free)


func setup(label_text, color):
	text = str(label_text)
	add_theme_color_override("font_color", color)
	modulate = Color.WHITE
