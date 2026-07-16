extends SceneTree

const MANIFEST_PATH = "res://tools/asset_manifest.json"
const CHROMA_HARD_THRESHOLD = 0.22
const CHROMA_SOFT_THRESHOLD = 0.35
const ALPHA_CUTOFF = 8
const BOTTOM_MARGIN_PX = 4
const PLACEHOLDER_BORDER_PX = 2


func _initialize():
	quit(_run())


func _run():
	var args = _parse_args()
	if args["error"] != "":
		print("ERROR: " + args["error"])
		return 1

	var manifest_result = _load_manifest()
	if manifest_result["error"] != "":
		print("ERROR: " + manifest_result["error"])
		return 1

	var manifest = manifest_result["manifest"]
	var palette = _parse_palette(manifest.get("palette", []))
	var assets = manifest.get("assets", [])
	var processed = 0
	var skipped = 0
	var errors = []
	var found_only = args["only"] == ""

	for asset in assets:
		var id = str(asset.get("id", ""))
		if args["only"] != "" and id != args["only"]:
			continue
		found_only = true

		if args["placeholders"]:
			var placeholder_error = _write_placeholder(asset, palette)
			if placeholder_error == "":
				processed += 1
				print("PLACEHOLDER " + id + " -> " + str(asset.get("target", "")))
			else:
				errors.append(id + ": " + placeholder_error)
			continue

		var source_path = _project_path(str(asset.get("source", "")))
		if not FileAccess.file_exists(source_path):
			skipped += 1
			print("SKIP " + id + " missing source " + str(asset.get("source", "")))
			continue

		var process_error = _process_asset(asset, palette)
		if process_error == "":
			processed += 1
			print("PROCESSED " + id + " -> " + str(asset.get("target", "")))
		else:
			errors.append(id + ": " + process_error)

	if not found_only:
		errors.append("unknown --only id: " + args["only"])

	print("ASSET PIPELINE SUMMARY: processed=%d skipped=%d errors=%d" % [processed, skipped, errors.size()])
	for error in errors:
		print("ERROR: " + error)
	return 0 if errors.is_empty() else 1


func _parse_args():
	var result = {
		"placeholders": false,
		"only": "",
		"error": "",
	}
	var args = OS.get_cmdline_user_args()
	var index = 0
	while index < args.size():
		var arg = str(args[index])
		if arg == "--":
			pass
		elif arg == "--placeholders":
			result["placeholders"] = true
		elif arg == "--only":
			index += 1
			if index >= args.size():
				result["error"] = "--only requires an asset id"
				return result
			result["only"] = str(args[index])
		elif arg.begins_with("--only="):
			result["only"] = arg.substr("--only=".length())
		else:
			result["error"] = "unknown argument: " + arg
			return result
		index += 1
	return result


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
	var text = file.get_as_text()
	var json = JSON.new()
	var parse_error = json.parse(text)
	if parse_error != OK:
		result["error"] = "manifest JSON parse failed at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result["error"] = "manifest root must be an object"
		return result
	result["manifest"] = json.data
	return result


func _process_asset(asset, palette):
	var source_path = _project_path(str(asset.get("source", "")))
	var image = Image.new()
	var load_error = image.load(source_path)
	if load_error != OK:
		return "failed to load source %s error=%d" % [source_path, load_error]
	image.convert(Image.FORMAT_RGBA8)

	var chroma = asset.get("chroma", null)
	if chroma != null:
		_apply_chroma_key(image, Color.html(str(chroma)))

	if str(asset.get("anchor", "fill")) != "fill":
		image = _trim_alpha(image)
		image = _pad_bottom_for_anchor(image, asset)

	var pixel_grid = _vector2i_from_array(asset.get("pixel_grid", [1, 1]))
	image.resize(pixel_grid.x, pixel_grid.y, Image.INTERPOLATE_LANCZOS)
	if bool(asset.get("remap", false)):
		_remap_to_palette(image, palette)

	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [1, 1]))
	image.resize(pixel_grid.x * 2, pixel_grid.y * 2, Image.INTERPOLATE_NEAREST)
	var canvas = _compose_canvas(image, asset, canvas_px)
	if str(asset.get("anchor", "fill")) == "bottom_center":
		_clear_bottom_margin(canvas)

	return _save_image(canvas, str(asset.get("target", "")))


func _apply_chroma_key(image, chroma):
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x, y)
			var distance = _rgb_distance(color, chroma)
			if distance < CHROMA_HARD_THRESHOLD:
				color.a = 0.0
			elif distance < CHROMA_SOFT_THRESHOLD:
				var alpha_scale = (distance - CHROMA_HARD_THRESHOLD) / (CHROMA_SOFT_THRESHOLD - CHROMA_HARD_THRESHOLD)
				color.a *= clamp(alpha_scale, 0.0, 1.0)
			image.set_pixel(x, y, color)


func _trim_alpha(image):
	var min_x = image.get_width()
	var min_y = image.get_height()
	var max_x = -1
	var max_y = -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if int(round(image.get_pixel(x, y).a * 255.0)) >= ALPHA_CUTOFF:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	if max_x < min_x or max_y < min_y:
		return _create_image(1, 1)

	var trimmed = _create_image(max_x - min_x + 1, max_y - min_y + 1)
	trimmed.blit_rect(image, Rect2i(min_x, min_y, trimmed.get_width(), trimmed.get_height()), Vector2i.ZERO)
	return trimmed


func _pad_bottom_for_anchor(image, asset):
	if str(asset.get("anchor", "fill")) != "bottom_center":
		return image
	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [image.get_width(), image.get_height()]))
	var available = max(1.0, float(canvas_px.y - BOTTOM_MARGIN_PX))
	var pad_h = int(ceil(float(image.get_height()) * float(BOTTOM_MARGIN_PX) / available))
	if pad_h <= 0:
		return image
	var padded = _create_image(image.get_width(), image.get_height() + pad_h)
	padded.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	return padded


func _remap_to_palette(image, palette):
	if palette.is_empty():
		return
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x, y)
			if int(round(color.a * 255.0)) < ALPHA_CUTOFF:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var nearest = _nearest_palette_color(color, palette)
			image.set_pixel(x, y, Color(nearest.r, nearest.g, nearest.b, color.a))


func _nearest_palette_color(color, palette):
	var best = palette[0]
	var best_distance = INF
	for candidate in palette:
		var distance = _rgb_distance(color, candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _compose_canvas(image, asset, canvas_px):
	var canvas = _create_image(canvas_px.x, canvas_px.y)
	var anchor = str(asset.get("anchor", "fill"))
	var position = Vector2i.ZERO
	if anchor == "bottom_center":
		position.x = int(round(float(canvas_px.x - image.get_width()) * 0.5))
		position.y = max(0, canvas_px.y - BOTTOM_MARGIN_PX - image.get_height())
	canvas.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), position)
	return canvas


func _write_placeholder(asset, palette):
	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [1, 1]))
	var image = _create_image(canvas_px.x, canvas_px.y)
	var id = str(asset.get("id", ""))
	var hash_value = _stable_hash(id)
	var base = _placeholder_color(hash_value, palette, 3)
	var accent = _placeholder_color(hash_value, palette, 11)
	var shadow = _placeholder_color(hash_value, palette, 17)
	var chroma = asset.get("chroma", null)
	var anchor = str(asset.get("anchor", "fill"))
	var transparent_border = 0
	if chroma != null:
		transparent_border = int(clamp(min(canvas_px.x, canvas_px.y) / 10, 4, 10))
	var bottom_clear = BOTTOM_MARGIN_PX if anchor == "bottom_center" else 0
	var rect = Rect2i(
		transparent_border,
		transparent_border,
		max(1, canvas_px.x - transparent_border * 2),
		max(1, canvas_px.y - transparent_border * 2 - bottom_clear)
	)

	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var color = base
			if ((x + y + hash_value) % 17) == 0:
				color = accent
			elif ((x - y + hash_value) % 23) == 0:
				color = shadow
			image.set_pixel(x, y, color)

	_draw_placeholder_frame(image, rect, accent, shadow)
	_draw_placeholder_mark(image, rect, hash_value, accent, shadow)

	if bool(asset.get("seamless_x", false)):
		_enforce_seamless_x_placeholder(image, base)
	if anchor == "bottom_center":
		_clear_bottom_margin(image)

	return _save_image(image, str(asset.get("target", "")))


func _draw_placeholder_frame(image, rect, accent, shadow):
	for offset in range(PLACEHOLDER_BORDER_PX):
		var left = rect.position.x + offset
		var right = rect.position.x + rect.size.x - 1 - offset
		var top = rect.position.y + offset
		var bottom = rect.position.y + rect.size.y - 1 - offset
		for x in range(left, right + 1):
			image.set_pixel(x, top, accent)
			image.set_pixel(x, bottom, shadow)
		for y in range(top, bottom + 1):
			image.set_pixel(left, y, accent)
			image.set_pixel(right, y, shadow)


func _draw_placeholder_mark(image, rect, hash_value, accent, shadow):
	var center = rect.position + rect.size / 2
	var radius = max(3, min(rect.size.x, rect.size.y) / 5)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var dx = abs(x - center.x)
			var dy = abs(y - center.y)
			if dx + dy == radius:
				image.set_pixel(x, y, accent)
			elif hash_value % 2 == 0 and abs(dx - dy) == 0 and dx < radius:
				image.set_pixel(x, y, shadow)
			elif hash_value % 2 != 0 and dx < radius and dy == 0:
				image.set_pixel(x, y, shadow)


func _enforce_seamless_x_placeholder(image, edge_color):
	for y in range(image.get_height()):
		image.set_pixel(0, y, edge_color)
		image.set_pixel(image.get_width() - 1, y, edge_color)


func _clear_bottom_margin(image):
	for y in range(max(0, image.get_height() - BOTTOM_MARGIN_PX), image.get_height()):
		for x in range(image.get_width()):
			image.set_pixel(x, y, Color(0, 0, 0, 0))


func _save_image(image, target):
	if target == "":
		return "target is empty"
	var target_path = _project_path(target)
	var target_dir = target_path.get_base_dir()
	var mkdir_error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	if mkdir_error != OK:
		return "failed to create target dir %s error=%d" % [target_dir, mkdir_error]
	var save_error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		return "failed to save %s error=%d" % [target, save_error]
	return ""


func _parse_palette(values):
	var palette = []
	for value in values:
		palette.append(Color.html(str(value)))
	return palette


func _placeholder_color(hash_value, palette, offset):
	if palette.is_empty():
		return Color(1, 1, 1, 1)
	var index = abs(hash_value + offset) % palette.size()
	var color = palette[index]
	color.a = 1.0
	return color


func _rgb_distance(a, b):
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _vector2i_from_array(value):
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return Vector2i.ONE
	return Vector2i(int(value[0]), int(value[1]))


func _create_image(width, height):
	var image = Image.create(max(1, width), max(1, height), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _project_path(path):
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path


func _stable_hash(text):
	var hash_value = 2166136261
	for index in range(text.length()):
		hash_value = int((hash_value ^ text.unicode_at(index)) * 16777619) & 0x7fffffff
	return hash_value
