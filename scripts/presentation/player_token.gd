extends Node2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

const IDLE_TEXTURES = [
	preload("res://assets/textures/chars/player_idle_f1.png"),
	preload("res://assets/textures/chars/player_idle_f2.png"),
]
const SPRITE_SIZE = Vector2(88.0, 132.0)

var body_root = null
var sprite = null
var idle_timer = null
var idle_frame = 0
var state_key = {}


func _ready():
	_build_body()


func set_display(is_visible, coord):
	var next_key = {
		"visible": bool(is_visible),
		"coord": coord,
	}
	if next_key == state_key:
		return
	state_key = next_key
	visible = bool(is_visible)
	position = ViewConfig.entity_anchor(coord)
	queue_redraw()


func _draw():
	if not visible:
		return
	_draw_shadow(Vector2(0.0, -2.0), Vector2(24.0, 7.0), Color(0.0, 0.0, 0.0, 0.24))


func _build_body():
	body_root = Node2D.new()
	body_root.name = "BodyRoot"
	add_child(body_root)

	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture = IDLE_TEXTURES[0]
	sprite.position = Vector2(-SPRITE_SIZE.x * 0.5, -SPRITE_SIZE.y)
	body_root.add_child(sprite)

	idle_timer = Timer.new()
	idle_timer.name = "IdleFrameTimer"
	idle_timer.wait_time = FxConfig.IDLE_FRAME_SEC
	idle_timer.autostart = true
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	add_child(idle_timer)


func _on_idle_timer_timeout():
	idle_frame = 1 - idle_frame
	sprite.texture = IDLE_TEXTURES[idle_frame]


func _draw_shadow(center, scale, color):
	draw_set_transform(center, 0.0, scale)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
