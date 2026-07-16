extends RefCounted

# The cell footprint is the single world-space unit for the board.
# Tiles draw inside the footprint with an inset, while future tall sprites should
# stand on entity_anchor() and extend upward over previous rows.
const CELL_SIZE_PX = 88.0
const CELL_INSET_PX = 2.0
const TILE_THICKNESS_PX = 10.0 # 未開放タイルの前面(下辺)の厚み。3/4見下ろしの立体感
const TOKEN_HEIGHT_PX = 104.0 # キャラトークンの高さ(セル88pxより背が高く、上のセルに重なる)
const FIT_MARGIN_PX = 16.0
const FIT_MAX_ZOOM = 1.0
const MIN_ZOOM = 0.5
const MAX_ZOOM = 2.0
const DEFAULT_ZOOM = 1.0
const ZOOM_WHEEL_STEP = 1.1
const ZOOM_STEPS = [0.5, 0.75, 1.0, 1.5, 2.0]


static func world_pos(coord):
	return Vector2(coord.x, coord.y) * CELL_SIZE_PX


static func cell_center(coord):
	return world_pos(coord) + Vector2.ONE * CELL_SIZE_PX * 0.5


static func entity_anchor(coord):
	return Vector2((coord.x + 0.5) * CELL_SIZE_PX, (coord.y + 1.0) * CELL_SIZE_PX)
