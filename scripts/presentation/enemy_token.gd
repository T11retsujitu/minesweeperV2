extends Node2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

const IDLE_TEXTURES = [
	preload("res://assets/textures/chars/slime_idle_f1.png"),
	preload("res://assets/textures/chars/slime_idle_f2.png"),
]
const SPRITE_SIZE = Vector2(88.0, 96.0)
const FLASH_SHADER_CODE = """
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	tex.rgb = mix(tex.rgb, vec3(1.0), flash_amount * tex.a);
	COLOR = tex;
}
"""

var countdown = 0
var pulse_tween = null
var hit_tween = null
var pulse_active = false
var body_root = null
var sprite = null
var sprite_flash_material = null
var idle_timer = null
var idle_frame = 0
var idle_timer_first_tick = true
var state_key = {}
var current_coord = Vector2i.ZERO


func _ready():
	_build_body()


func set_display(is_visible, coord, next_countdown):
	var next_key = {
		"visible": bool(is_visible),
		"coord": coord,
		"countdown": int(next_countdown),
	}
	if next_key == state_key:
		return
	state_key = next_key
	visible = bool(is_visible)
	countdown = int(next_countdown)
	current_coord = coord
	position = ViewConfig.entity_anchor(coord)
	_reset_hit_reaction()
	if visible and countdown == 1:
		_start_pulse()
	else:
		_stop_pulse()
	queue_redraw()


func play_mine_hit_reaction(source_world_pos):
	if not visible or body_root == null:
		return
	if hit_tween != null:
		hit_tween.kill()
		hit_tween = null

	var direction = position - source_world_pos
	if direction.length() <= 0.001:
		direction = Vector2.UP
	direction = direction.normalized()

	body_root.position = Vector2.ZERO
	_set_sprite_flash_amount(1.0)
	hit_tween = create_tween()
	hit_tween.set_ignore_time_scale(true)
	hit_tween.set_parallel(true)
	hit_tween.tween_property(body_root, "position", direction * FxConfig.ENEMY_HIT_KNOCKBACK_PX, FxConfig.ENEMY_HIT_KNOCKBACK_OUT_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_method(Callable(self, "_set_sprite_flash_amount"), 1.0, 0.0, FxConfig.ENEMY_HIT_FLASH_SEC)
	hit_tween.chain().tween_property(body_root, "position", Vector2.ZERO, FxConfig.ENEMY_HIT_KNOCKBACK_RETURN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	hit_tween.finished.connect(_on_hit_reaction_finished)


func get_coord():
	return current_coord


func _draw():
	if not visible:
		return
	_draw_shadow(Vector2(0.0, -2.0), Vector2(27.0, 8.0), Color(0.0, 0.0, 0.0, 0.30))
	var rect = _badge_rect()
	var color = FxConfig.COLOR_ENEMY_BADGE
	var text = str(countdown)
	if countdown == 1:
		color = FxConfig.COLOR_ENEMY_BADGE_DANGER
		text = "1!"
	draw_rect(rect, color)
	_draw_badge_text(rect, text)


func _badge_rect():
	return Rect2(
		Vector2(
			-FxConfig.ENEMY_BADGE_SIZE * 0.5,
			-SPRITE_SIZE.y - FxConfig.ENEMY_BADGE_SIZE - 6.0
		),
		Vector2(FxConfig.ENEMY_BADGE_SIZE, FxConfig.ENEMY_BADGE_SIZE)
	)


func _build_body():
	body_root = Node2D.new()
	body_root.name = "BodyRoot"
	add_child(body_root)

	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture = IDLE_TEXTURES[0]
	sprite.position = Vector2(-SPRITE_SIZE.x * 0.5, -SPRITE_SIZE.y)
	var shader = Shader.new()
	shader.code = FLASH_SHADER_CODE
	sprite_flash_material = ShaderMaterial.new()
	sprite_flash_material.shader = shader
	sprite_flash_material.set_shader_parameter("flash_amount", 0.0)
	sprite.material = sprite_flash_material
	body_root.add_child(sprite)

	idle_timer = Timer.new()
	idle_timer.name = "IdleFrameTimer"
	idle_timer.wait_time = FxConfig.IDLE_FRAME_SEC * 0.5
	idle_timer.autostart = true
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	add_child(idle_timer)


func _on_idle_timer_timeout():
	if idle_timer_first_tick:
		idle_timer_first_tick = false
		idle_timer.wait_time = FxConfig.IDLE_FRAME_SEC
		idle_timer.start()
	idle_frame = 1 - idle_frame
	sprite.texture = IDLE_TEXTURES[idle_frame]


func _draw_shadow(center, scale, color):
	draw_set_transform(center, 0.0, scale)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_badge_text(rect, text):
	var font = ThemeDB.fallback_font
	var font_size = FxConfig.ENEMY_BADGE_FONT_SIZE
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline = rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var pos = Vector2(rect.position.x + (rect.size.x - text_size.x) * 0.5, baseline)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _start_pulse():
	if pulse_active:
		return
	_stop_pulse()
	pulse_active = true
	pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(self, "modulate:a", FxConfig.ENEMY_BADGE_PULSE_ALPHA, FxConfig.ENEMY_BADGE_PULSE_SEC)
	pulse_tween.tween_property(self, "modulate:a", 1.0, FxConfig.ENEMY_BADGE_PULSE_SEC)


func _stop_pulse():
	pulse_active = false
	if pulse_tween != null:
		pulse_tween.kill()
		pulse_tween = null
	modulate = Color.WHITE


func _reset_hit_reaction():
	if hit_tween != null:
		hit_tween.kill()
		hit_tween = null
	if body_root != null:
		body_root.position = Vector2.ZERO
	_set_sprite_flash_amount(0.0)


func _set_sprite_flash_amount(value):
	if sprite_flash_material != null:
		sprite_flash_material.set_shader_parameter("flash_amount", value)


func _on_hit_reaction_finished():
	hit_tween = null
	if body_root != null:
		body_root.position = Vector2.ZERO
	_set_sprite_flash_amount(0.0)
