extends SceneTree

const MANIFEST_PATH = "res://tools/asset_manifest.json"
const BOTTOM_MARGIN_PX = 4
const SEAMLESS_AVG_DIFF_MAX = 0.08


func _initialize():
	quit(_run())


func _run():
	var manifest_result = _load_manifest()
	if manifest_result["error"] != "":
		print("ERROR: " + manifest_result["error"])
		return 1

	var manifest = manifest_result["manifest"]
	var palette_keys = _palette_keys(manifest.get("palette", []))
	var assets = manifest.get("assets", [])
	var passed = 0
	var failed = 0
	var skipped = 0

	for asset in assets:
		var id = str(asset.get("id", ""))
		var target = str(asset.get("target", ""))
		var required = bool(asset.get("required", true))
		var target_path = _project_path(target)

		if not FileAccess.file_exists(target_path):
			if required:
				failed += 1
				print("FAIL " + id + ": missing target " + target)
			else:
				skipped += 1
				print("SKIP " + id + ": optional target missing")
			continue

		var issues = _check_asset(asset, palette_keys)
		if issues.is_empty():
			passed += 1
			print("PASS " + id)
		else:
			failed += 1
			print("FAIL " + id + ": " + "; ".join(issues))

	print("ASSET CHECK SUMMARY: pass=%d skip=%d fail=%d" % [passed, skipped, failed])
	return 0 if failed == 0 else 1


func _load_manifest():
	var result = {
		"manifest": {},
		"error": "",
	}
	if not FileAccess.file_exists(MANIFEST_PATH):
		result["error"] = "manifest not found: " + MANIFEST_PATH
		return result
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		result["error"] = "failed to open manifest: " + MANIFEST_PATH
		return result
	var json = JSON.new()
	var parse_error = json.parse(file.get_as_text())
	if parse_error != OK:
		result["error"] = "manifest JSON parse failed at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result["error"] = "manifest root must be an object"
		return result
	result["manifest"] = json.data
	return result


func _check_asset(asset, palette_keys):
	var issues = []
	var target_path = _project_path(str(asset.get("target", "")))
	var image = Image.new()
	var load_error = image.load(target_path)
	if load_error != OK:
		return ["failed to load target error=%d" % load_error]
	image.convert(Image.FORMAT_RGBA8)

	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [1, 1]))
	if image.get_width() != canvas_px.x or image.get_height() != canvas_px.y:
		issues.append("size expected=%s actual=%dx%d" % [str(canvas_px), image.get_width(), image.get_height()])
		return issues

	if asset.get("chroma", null) != null and not _corners_are_transparent(image):
		issues.append("chroma corners are not transparent")

	if bool(asset.get("seamless_x", false)):
		var diff = _average_edge_diff(image)
		if diff > SEAMLESS_AVG_DIFF_MAX:
			issues.append("seamless_x average edge diff %.4f > %.4f" % [diff, SEAMLESS_AVG_DIFF_MAX])

	if str(asset.get("anchor", "fill")) == "bottom_center" and not _bottom_margin_is_transparent(image):
		issues.append("bottom_center bottom %dpx are not fully transparent" % BOTTOM_MARGIN_PX)

	if bool(asset.get("remap", false)):
		var off_palette = _count_off_palette_pixels(image, palette_keys)
		if off_palette > 0:
			issues.append("palette off-color pixels=%d" % off_palette)

	return issues


func _corners_are_transparent(image):
	var points = [
		Vector2i(0, 0),
		Vector2i(image.get_width() - 1, 0),
		Vector2i(0, image.get_height() - 1),
		Vector2i(image.get_width() - 1, image.get_height() - 1),
	]
	for point in points:
		if image.get_pixel(point.x, point.y).a > 0.0:
			return false
	return true


func _average_edge_diff(image):
	var total = 0.0
	for y in range(image.get_height()):
		var left = image.get_pixel(0, y)
		var right = image.get_pixel(image.get_width() - 1, y)
		total += _rgb_distance(left, right)
	return total / max(1.0, float(image.get_height()))


func _bottom_margin_is_transparent(image):
	for y in range(max(0, image.get_height() - BOTTOM_MARGIN_PX), image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				return false
	return true


func _count_off_palette_pixels(image, palette_keys):
	var off_palette = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			if not palette_keys.has(_rgb_key(color)):
				off_palette += 1
	return off_palette


func _palette_keys(values):
	var keys = {}
	for value in values:
		var color = Color.html(str(value))
		keys[_rgb_key(color)] = true
	return keys


func _rgb_key(color):
	return "%02x%02x%02x" % [
		int(round(clamp(color.r, 0.0, 1.0) * 255.0)),
		int(round(clamp(color.g, 0.0, 1.0) * 255.0)),
		int(round(clamp(color.b, 0.0, 1.0) * 255.0)),
	]


func _rgb_distance(a, b):
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _vector2i_from_array(value):
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return Vector2i.ONE
	return Vector2i(int(value[0]), int(value[1]))


func _project_path(path):
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path
