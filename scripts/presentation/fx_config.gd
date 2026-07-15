# 演出専用定数。ゲームルール値は scripts/config/game_balance.gd(凍結)にあり、ここには置かない
extends RefCounted

const FLOAT_DURATION = 0.7
const FLOAT_RISE_PX = 46.0
const FLOAT_FONT_SIZE = 26
const PROJECTILE_TIME = 0.28
const PROJECTILE_SIZE = 10.0
const EXPLOSION_RING_DELAY = 0.07
const SHAKE_AMPLITUDE = 7.0
const SHAKE_DURATION = 0.22
const HIT_STOP_SEC = 0.06
const HIT_STOP_TIME_SCALE = 0.05
const HP_TWEEN_SEC = 0.28
const LABEL_FLASH_SEC = 0.28
const EXPLOSION_FLASH_SEC = 0.42
const TERMINAL_FADE_SEC = 0.3

const COLOR_DAMAGE_ENEMY_ATK = Color(1.0, 0.35, 0.22)
const COLOR_DAMAGE_MINE = Color(1.0, 0.62, 0.18)
const COLOR_DAMAGE_DEALT = Color(1.0, 0.85, 0.30)
const COLOR_ENEMY_ATTACK_STATUS = Color(1.0, 0.55, 0.18)
