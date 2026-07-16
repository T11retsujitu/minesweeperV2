# アーキテクチャ

## レイヤ構成と依存方向

```
presentation (Node/Control)  ── 描画・入力通知のみ。ルール判定なし
      │  snapshot / events      ※ 盤面は Node2D ワールド+Camera2D(規約は docs/view-spec.md)
application (RefCounted)     ── BattleController: 入力ロック、意図→ドメイン変換
      │
domain (RefCounted)          ── ルールの正本。Node/UI/シーン非依存
      │
config (const)               ── game_balance.gd: 全数値の唯一の置き場
generation (static)          ── 固定盤面データ + シード付きランダム生成
```

依存は上から下への一方向のみ。preload の層順は `cell ← board ← state ← resolver` で固定し循環参照を禁止(RefCounted は循環でリークするため)。`class_name` は使わず全て `preload()` 参照(fresh clone でもヘッドレス実行が決定的)。autoload・汎用イベントバスは使わない。

## 状態の正本(single source of truth)

1戦闘の全状態は `CombatState` 1つに集約される:

- `board`(BoardModel: W×H 個の CellModel。固定=7×7 / avatarランダム=12×12)/ `enemy` / `player`
- `turn_count` / `seed` / `mode`(fixed|random)/ `phase`(playing|**recovery**|victory|defeat)/ `ruleset`(phase1|phase2_avatar)
- `action_log`(文字列配列)/ `first_reveal_done` / `used_fixture_fallback` / `accidental_mine_count`
- snapshot 追加キー(avatar): `player_position` / `movable_cells` / `revealable_cells` / `bumpable_cells` / `territory_cells` / `player_in_territory` / `safe_cells_total` / `safe_cells_revealed` / `board_width` / `board_height`

UI は `controller.get_snapshot()` が返す辞書(セル状態・HP・カウントダウン・ログ等)だけから描画する。UI側に状態の複製を持たない。

## ターン解決フロー

```
入力(tap/long_press/confirm)
  → BattleController(is_busy なら拒否 / フラグはターン非消費で board 直接)
  → TurnResolver.resolve(state, action)   ※ handoff §5.8 の順序で同期実行
      1. 入力検証 → 2. 開放/起爆/移動/bump/除去 → 3. ダメージ適用 → 4. 敵死亡
      → 5. 勝利判定(phase1=即victory / avatar=combat_won→PHASE_RECOVERY遷移、D28)
      → 6. 敵カウント減(avatar は縄張り内のときのみ。圏外は countdown_paused、D31)
      → 7. カウント0なら敵攻撃+リセット → 8-9. プレイヤー死亡/敗北 → 10. イベント返却
      ※ PHASE_RECOVERY 中は 6-7 を全スキップし、死亡判定+Perfect Clear 判定のみ
  → controller が is_busy=true にして events_emitted シグナル発火
  → presentation がイベントを消費して演出再生(ロジックは確定済み)
  → 演出完了後 controller.notify_effects_done() で is_busy 解除
```

演出はゲーム状態を変更しない。演出中の入力は controller(is_busy)と presentation(オーバーレイ判定)の二重で拒否される。

## イベントカタログ

`TurnResolver.resolve` / controller が返す Dictionary 配列。`type` キーで判別:

| type | 発生元 | 主なペイロード |
|------|--------|----------------|
| `cells_revealed` | 開放/フラッド/dud | cells, trigger |
| `mine_exploded` | 起爆/誤爆 | cell, accidental |
| `dud_detonation` | 不発起爆 | cell |
| `enemy_damaged` / `player_damaged` | 爆発/敵攻撃 | before, after, amount(, source) |
| `enemy_died` / `victory` / `defeat` | 解決順序 4/5/9 | turn_count(avatar の victory は + perfect: bool) |
| `combat_won` | 敵撃破→回収フェーズ遷移(avatar、D28) | turn_count |
| `perfect_clear` | 全安全セル開放(avatar、D28) | turn_count |
| `countdown_changed` / `enemy_attacked` | 解決順序 6/7 | before, after / damage |
| `countdown_paused` | 縄張り圏外でカウント凍結(avatar、D31) | countdown |
| `player_moved` | 移動(avatar) | from, to |
| `enemy_bumped` | bump攻撃(avatar、D32。反撃は player_damaged{source:"bump_counter"}) | cell, damage |
| `mine_defused` / `defuse_dud` | 地雷除去/誤フラグ除去(avatar、D33) | cell, damage / cell |
| `flag_toggled` | controller | cell, flagged |
| `detonation_preview` / `detonation_cancelled` | controller | cell, preview |
| `mine_relocated` | 初手安全(random) | from, to |
| `turn_rejected` | 各層の拒否 | reason |
| `state_reset` | retry/mode/seed変更 | reason |

## 盤面ルールの実装箇所

- 隣接地雷数・フラッド(0連鎖のキュー式開放)・フラグ・起爆・爆発範囲: `BoardModel`
- 隣接計算は固定の8近傍(`ADJACENCY_RADIUS = 1`、ルール定義であり調整値ではない)。爆発範囲は `EXPLOSION_RADIUS_CHEBYSHEV`(調整値)で別管理
- フラッドは「hidden かつ 未フラグ かつ 非detonated」のみ開放
- `preview_detonation(cell)` は座標のみから予想ダメージを計算(`contains_mine` 非依存 → dud でも情報リークしない)
- 起爆済み(detonated)セルは以後非インタラクティブ

## 生成

- **固定盤面**: `fixtures.gd` の `phase1_core_demo`(座標リスト)。initial_revealed は明示リストのみ開放(フラッドしない)
- **ランダム**: `RandomNumberGenerator` にシードを明示設定。敵は内側に配置し、敵3×3ゾーンに地雷ちょうど3個。試行上限100回、失敗時は fixture にフォールバック(`used_fixture_fallback`)。盤面サイズは `board_config` 引数で指定 — **null なら従来の 7×7/9(phase1 とテスト互換)、avatar の MODE_RANDOM は 12×12/26**(`RANDOM_BOARD_W/H/MINE_COUNT`、D34)
- **初手安全(randomのみ)**: 最初の REVEAL が地雷なら、`hash(seed, タップ座標)` で決定的に移設(ゾーン地雷はゾーン内へ→3個保証維持、開放済み・敵セル・既存地雷は除外)して数字再計算

## テスト

`tests/run_tests.gd`(SceneTree 継承)が各テストファイルの `run(t)` を呼び、失敗メッセージを収集して最後にサマリ出力・exit 0/1。`assert()` は使わない(全件実行のため)。全テストは UI 非依存で、固定盤面の**正解グリッド**(docs/implementation-plan.md §3)と **E2E勝利/敗北ライン**を含む。
