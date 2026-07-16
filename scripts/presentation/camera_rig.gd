extends Camera2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const CameraMath = preload("res://scripts/presentation/camera_math.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var shake_generation = 0
var view_center = Vector2.ZERO
var zoom_scalar = 1.0
var punch_scale = 1.0:
	set(value):
		punch_scale = value
		_apply_camera_state()
var punch_world_target = Vector2.ZERO
var punch_tween = null
var board_rect = Rect2()
var slot_rect = Rect2()


func _ready():
	position_smoothing_enabled = false
	offset = Vector2.ZERO
	make_current()


func refit(board_w, board_h, next_slot_rect, focus_world = null):
	var board_px = Vector2(board_w, board_h) * ViewConfig.CELL_SIZE_PX
	if board_px.x <= 0.0 or board_px.y <= 0.0:
		return
	if next_slot_rect.size.x <= 1.0 or next_slot_rect.size.y <= 1.0:
		return

	board_rect = Rect2(Vector2.ZERO, board_px)
	slot_rect = next_slot_rect
	var board_center = board_px * 0.5
	var fit = CameraMath.fit_zoom(board_px, slot_rect.size, ViewConfig.FIT_MARGIN_PX)
	if fit >= ViewConfig.MIN_ZOOM:
		zoom_scalar = clamp(fit, ViewConfig.MIN_ZOOM, ViewConfig.FIT_MAX_ZOOM)
		view_center = board_center
	else:
		zoom_scalar = clamp(ViewConfig.DEFAULT_ZOOM, ViewConfig.MIN_ZOOM, ViewConfig.MAX_ZOOM)
		if focus_world == null:
			view_center = board_center
		else:
			view_center = focus_world
	view_center = CameraMath.clamp_center(view_center, zoom_scalar, board_rect, slot_rect.size)
	_apply_camera_state()


func pan_by_screen_delta(delta):
	if slot_rect.size == Vector2.ZERO:
		return
	view_center = CameraMath.pan_center(view_center, delta, zoom_scalar)
	view_center = CameraMath.clamp_center(view_center, zoom_scalar, board_rect, slot_rect.size)
	_apply_camera_state()


func zoom_at(anchor_screen, new_zoom):
	if slot_rect.size == Vector2.ZERO:
		return
	var clamped_zoom = clamp(new_zoom, ViewConfig.MIN_ZOOM, ViewConfig.MAX_ZOOM)
	view_center = CameraMath.zoom_at_point(zoom_scalar, clamped_zoom, anchor_screen, view_center, slot_rect.get_center())
	zoom_scalar = clamped_zoom
	view_center = CameraMath.clamp_center(view_center, zoom_scalar, board_rect, slot_rect.size)
	_apply_camera_state()


func get_zoom_scalar():
	return zoom_scalar


func get_view_center():
	return view_center


func debug_state():
	return {
		"center": view_center,
		"zoom": zoom_scalar,
	}


func shake(amplitude_scale := 1.0):
	var generation = shake_generation
	var elapsed = 0.0
	var step_sec = 0.025
	var rng = RandomNumberGenerator.new()
	while elapsed < FxConfig.SHAKE_DURATION and generation == shake_generation:
		offset = Vector2(
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE),
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE)
		) * amplitude_scale
		var wait_sec = min(step_sec, FxConfig.SHAKE_DURATION - elapsed)
		await get_tree().create_timer(wait_sec).timeout
		elapsed += wait_sec
	if generation == shake_generation:
		offset = Vector2.ZERO


func reset_shake():
	shake_generation += 1
	offset = Vector2.ZERO


func punch(world_target):
	if punch_tween != null:
		punch_tween.kill()
		punch_tween = null
	punch_world_target = world_target
	punch_scale = 1.0
	punch_tween = create_tween()
	punch_tween.set_ignore_time_scale(true)
	punch_tween.tween_property(self, "punch_scale", FxConfig.PUNCH_ZOOM_SCALE, FxConfig.PUNCH_ZOOM_IN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	punch_tween.tween_property(self, "punch_scale", 1.0, FxConfig.PUNCH_ZOOM_OUT_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	punch_tween.finished.connect(_on_punch_finished)


func reset_punch():
	if punch_tween != null:
		punch_tween.kill()
		punch_tween = null
	punch_world_target = Vector2.ZERO
	punch_scale = 1.0
	_apply_camera_state()


func _apply_camera_state():
	var effective_zoom = zoom_scalar * punch_scale
	if effective_zoom <= 0.0:
		return
	var effective_center = view_center
	if not is_equal_approx(punch_scale, 1.0):
		effective_center = punch_world_target + (view_center - punch_world_target) / punch_scale
	zoom = Vector2.ONE * effective_zoom
	var slot_center = slot_rect.get_center()
	var viewport_size = get_viewport_rect().size
	position = effective_center - (slot_center - viewport_size * 0.5) / effective_zoom


func _on_punch_finished():
	punch_tween = null
	punch_scale = 1.0
