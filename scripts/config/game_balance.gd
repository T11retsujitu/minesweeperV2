extends RefCounted

const BOARD_W = 7
const BOARD_H = 7
const MINE_COUNT = 9

const EXPLOSION_CENTER_DAMAGE = 4
const EXPLOSION_ADJACENT_DAMAGE = 2
const EXPLOSION_RADIUS_CHEBYSHEV = 1

const ENEMY_MAX_HP = 6
const ENEMY_ATTACK = 2
const ENEMY_COUNTDOWN = 3
const ENEMY_ZONE_MINES = 3
# 敵の攻撃圏(Chebyshev)。EXPLOSION_RADIUS_CHEBYSHEV(爆発)やADJACENCY_RADIUS(隣接)とは独立の調整値。
const TERRITORY_RADIUS = 2
const BUMP_DAMAGE = 1 # 起爆優位の担保: EXPLOSION_ADJACENT_DAMAGE より小さい近接フィニッシュ用。
const BUMP_COUNTER_DAMAGE = 2
const DEFUSE_DAMAGE = 2 # 自傷なしだが隣接コストを払うため、起爆隣接ダメージ以下に固定。

const PLAYER_MAX_HP = 10
const ACCIDENTAL_MINE_DAMAGE = 3

const GENERATION_MAX_TRIES = 100
const LONG_PRESS_SEC = 0.4
# 入力ジェスチャ: この距離を超えた押下移動はタップ/長押しではなくパン扱い。
const DRAG_TAP_CANCEL_PX = 12
