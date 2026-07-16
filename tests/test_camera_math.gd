extends RefCounted

const CameraMath = preload("res://scripts/presentation/camera_math.gd")


func run(t):
	_test_fit_zoom(t)
	_test_clamp_center(t)
	_test_zoom_at_point(t)
	_test_pan_center(t)


func _test_fit_zoom(t):
	_approx(t, CameraMath.fit_zoom(Vector2(1000, 500), Vector2(600, 600), 50.0), 0.5, "fit_zoom horizontal board uses width")
	_approx(t, CameraMath.fit_zoom(Vector2(500, 1000), Vector2(600, 600), 50.0), 0.5, "fit_zoom vertical board uses height")
	_approx(t, CameraMath.fit_zoom(Vector2(100, 100), Vector2(120, 120), 10.0), 1.0, "fit_zoom applies margin on both sides")


func _test_clamp_center(t):
	var board = Rect2(Vector2.ZERO, Vector2(1000, 800))
	_vec(t, CameraMath.clamp_center(Vector2(-100, -100), 1.0, board, Vector2(400, 300)), Vector2(200, 150), "clamp_center clamps top left")
	_vec(t, CameraMath.clamp_center(Vector2(1200, 1000), 1.0, board, Vector2(400, 300)), Vector2(800, 650), "clamp_center clamps bottom right")
	_vec(t, CameraMath.clamp_center(Vector2(500, 400), 1.0, board, Vector2(400, 300)), Vector2(500, 400), "clamp_center preserves in-range center")
	_vec(t, CameraMath.clamp_center(Vector2(0, 0), 1.0, Rect2(Vector2.ZERO, Vector2(100, 80)), Vector2(400, 300)), Vector2(50, 40), "clamp_center fixes small board to center")
	_vec(t, CameraMath.clamp_center(Vector2(0, 0), 1.0, Rect2(Vector2.ZERO, Vector2(400, 300)), Vector2(400, 300)), Vector2(200, 150), "clamp_center exact boundary centers board")
	_vec(t, CameraMath.clamp_center(Vector2(100, 400), 2.0, board, Vector2(400, 300)), Vector2(100, 400), "clamp_center zoomed range allows smaller visible width")
	_vec(t, CameraMath.clamp_center(Vector2(100, 400), 1.0, board, Vector2(400, 300)), Vector2(200, 400), "clamp_center wider visible range changes clamp limit")


func _test_zoom_at_point(t):
	var old_zoom = 1.0
	var new_zoom = 2.0
	var anchor = Vector2(400, 350)
	var slot_center = Vector2(300, 300)
	var center = Vector2(500, 400)
	var world_before = (anchor - slot_center) / old_zoom + center
	var new_center = CameraMath.zoom_at_point(old_zoom, new_zoom, anchor, center, slot_center)
	var world_after = (anchor - slot_center) / new_zoom + new_center
	_vec(t, world_after, world_before, "zoom_at_point keeps anchor world point fixed")
	_vec(t, CameraMath.zoom_at_point(new_zoom, old_zoom, anchor, new_center, slot_center), center, "zoom_at_point round-trips center")


func _test_pan_center(t):
	_vec(t, CameraMath.pan_center(Vector2(100, 100), Vector2(20, -10), 1.0), Vector2(80, 110), "pan_center moves opposite screen delta")
	_vec(t, CameraMath.pan_center(Vector2(100, 100), Vector2(20, -10), 2.0), Vector2(90, 105), "pan_center scales by inverse zoom")


func _approx(t, actual, expected, message):
	t.check(abs(actual - expected) <= 0.001, "%s | expected=%s actual=%s" % [message, str(expected), str(actual)])


func _vec(t, actual, expected, message):
	t.check(actual.distance_to(expected) <= 0.001, "%s | expected=%s actual=%s" % [message, str(expected), str(actual)])
