# Phase 1 実装計画 — Minesweeper Roguelite 戦闘垂直スライス

> 本書は `claude_code_initial_handoff_minesweeper_roguelite.md`(以下 handoff)に基づく Phase 1 の**拘束力のある実装仕様**である。
> 体制: Claude = 設計・オーケストレーション・検証、Codex = コーディング。実装者は本書と handoff §5(戦闘ルール)に従うこと。矛盾があれば本書が優先(handoff の曖昧箇所への裁定を含むため)。

## 1. 現状

- リポジトリ: handoff 文書のみ。エンジン・言語は未導入 → **Godot 4.4.1 + GDScript** を採用(handoff §2 準拠)。
- 実行環境: WSL2 x86_64、Godot バイナリは `~/.local/bin/godot`(4.4.1.stable 確認済み)。WSLg あり(ウィンドウ実行可)。
- ターゲット: Android 縦画面(将来)。Phase 1 は PC 上で操作可能にする。

## 2. 確定した設計判断(詳細理由は docs/decisions.md に記録)

1. レンダラ **gl_compatibility**、Viewport 720×1280 portrait、`canvas_items` stretch。
2. **dud起爆**: フラグ済みだが地雷でないセルの起爆確定 = 安全開放として解決(1ターン消費、ダメージ0、ログに dud 記録)。開いたセルが 0 なら通常どおりフラッド。
3. **数字は生成時固定**(起爆で地雷が消費されても隣接数を再計算しない)。
4. **爆発はセルを開放しない**(ダメージのみ)。爆心セルは detonated 状態になる。
5. **起爆後セルのライフサイクル**: 起爆時にフラグ自動除去。detonated セルは以後非インタラクティブ(タップ・フラグ・開放すべて無効)。誤爆セルは revealed + detonated。
6. **ランダム盤面は敵3×3内に地雷ちょうど3個**(= ceil(敵HP6 / 隣接ダメージ2)。handoff §5.2「最低1個」だと撃破不能盤面が生成されうるため強化)。残り6個はゾーン外。
7. **敵のランダム配置は内側 5×5**(x,y∈[1,5])。ゾーン8マス確保。敵セルの数字は常に3となり0にならない。
8. **first_reveal_safe はランダム盤面のみ**。初手が地雷なら該当地雷を空きセルへ移設(ゾーン地雷ならゾーン内空きへ移設し3個保証維持)し数字再計算。生成は試行上限100回+失敗時 fixture フォールバック。固定盤面は初手安全保証外。
9. **固定盤面の initial_revealed は明示リストのみ開放**(0セルでも自動展開しない。fixture は初期開放セルに0が無いよう設計済み)。
10. **勝敗同時成立は勝利優先**(handoff §5.8 の順序を字義どおり: 手順5で勝利すれば6-9を実行しない)。
11. **リトライは同一盤面**(fixed=同じfixture、random=同じseed)。新盤面は「New Seed」で明示的に。
12. **ターン解決はイベント配列を返す純粋ドメイン**。UI・ログはイベントを消費するだけ。演出はロジック確定後。
13. **ドメインの DETONATE は flagged セルのみ受理**。`preview_detonation` は `contains_mine` に依存せず座標のみから予想ダメージを計算(dud でも情報リークしない)。
14. **入力ロック**: controller はターン消費アクション受理時に `is_busy=true`、presentation の演出完了通知 `notify_effects_done()` で解除。解除前の入力は拒否。
15. **フラッドは hidden かつ 未フラグ かつ 非detonated のセルのみ開放**。
16. フラグ切替も `flag_toggled` イベントとして同一イベントストリームへ(ターン非消費)。
17. アクションログは handoff §10 書式(`Turn 1: reveal (2, 4) -> safe, adjacent=1` 形式)。
18. 起動時デフォルトは固定盤面モード。固定盤面時の Seed 欄は `fixture: phase1_core_demo` 表示。
19. 入力: PC = 左クリック開放/起爆確認、右クリック フラグ。タッチ = タップ / 長押し(秒数は config)。
20. コード識別子は英語、コメントとドキュメントは日本語。
21. 中心4ダメージは「爆心セルに敵がいる場合」のロジックとして実装(通常プレイでは敵セル=安全なので発生しないが、ドメインは任意状態を受け付けテストで検証する)。

## 3. 固定盤面 `phase1_core_demo`(検証済み — 座標変更禁止)

計画時にミニソルバー(全解列挙)で推理チェーン・勝敗ラインを検証済み。**この座標が正**。

```yaml
fixture_id: phase1_core_demo
board_size: [7, 7]          # x=0..6 (列), y=0..6 (行)
mines:                       # 9個
  - [0,1] / [1,1] / [4,1] / [6,1]
  - [0,3] / [6,3]
  - [3,4] / [5,5] / [6,5]
enemy: { position: [1,2], hp: 6 }
initial_revealed:            # 8セル(フラッド展開しない)
  - [1,2]                    # 敵セル =3
  - [2,1] / [3,1] / [2,2] / [3,2] / [1,3] / [2,3] / [3,3]   # すべて =1
```

全セル隣接数グリッド(**テストの正解値**。行=y、列=x、M=地雷):

```
y0: 2 2 1 1 1 2 1
y1: M M 1 1 M 2 M
y2: 3 3 1 1 1 3 2
y3: M 1 1 1 1 1 M
y4: 1 1 1 M 2 3 3
y5: 0 0 1 1 2 M M
y6: 0 0 0 0 1 2 2
```

推理構造: (2,2)=1 の未開放隣接は (1,1) のみ → 即確定。(1,2)=3 と (1,3)=1 の部分集合推理で (0,1) 確定。(1,4),(2,4) 開放後 (2,3)=1 から (3,4) 確定(敵射程外)、(2,4)=1 から (1,5) 安全 → 0フラッドで左下11マス開放 → (0,4)=1 から (0,3) 確定。敵隣接地雷はちょうど3個(2ダメージ×3=6=敵HP)。

**E2E勝利ライン(test_fixture_walkthrough が assert する正解)**:

| T | 行動 | 結果 |
|---|------|------|
| 1 | flag(1,1)→detonate(1,1) | 敵6→4、cd 3→2 |
| 2 | flag(0,1)→detonate(0,1) | 敵4→2、cd 2→1 |
| 3 | reveal(1,4)=1 | cd 1→0 → 敵攻撃 player 10→8、cd→3 |
| 4 | reveal(2,4)=1 | cd 3→2 |
| 5 | reveal(1,5)=0 | フラッドで11マス開放 {(0,4),(0,5),(0,6),(1,5),(1,6),(2,5),(2,6),(3,5),(3,6),(4,5),(4,6)}、cd 2→1 |
| 6 | flag(0,3)→detonate(0,3) | 敵2→0 → **勝利**(敵攻撃なし) |

(flag はターン非消費なのでターン数は表のとおり)

**E2E敗北ライン**: reveal(4,1)→HP7・cd2 / reveal(6,1)→HP4・cd1 / reveal(6,3)→HP1・cd0→敵攻撃2→HP-1 **敗北**(ターン3)。3発とも敵射程外(敵ダメージ0)であることも assert。

## 4. アーキテクチャ

```
res://
├─ project.godot / .gitignore / README.md
├─ scenes/
│  ├─ main.tscn                  # エントリ(デバッグ引数処理 → battle_screen)
│  └─ battle/{battle_screen,board_view,cell_view}.tscn
├─ scripts/
│  ├─ config/game_balance.gd     # 全調整値 const(下記)
│  ├─ domain/                    # RefCounted のみ。Node/UI/シーン依存 禁止
│  │  ├─ cell_model.gd           # coord, contains_mine, adjacent_mine_count, hidden|revealed, flag, intact|detonated
│  │  ├─ board_model.gd          # 隣接計算・開放・0フラッド(キュー式)・フラグ・起爆・起爆プレビュー
│  │  ├─ enemy_model.gd / player_model.gd
│  │  ├─ combat_state.gd         # 盤面+敵+プレイヤー+turn_count+seed+mode+phase+action_log
│  │  └─ turn_resolver.gd        # handoff §5.8 の 1-10 順序で解決、イベント配列を返す
│  ├─ generation/
│  │  ├─ fixtures.gd             # phase1_core_demo(§3 の座標を人間可読の定数データで)
│  │  └─ board_generator.gd      # fixture ロード / seed付きランダム生成+制約+上限+fallback
│  ├─ application/battle_controller.gd  # 入力ロック、意図→ドメイン、状態スナップショット
│  └─ presentation/{battle_screen,board_view,cell_view}.gd  # 描画と入力通知のみ。ルール判定禁止
├─ tests/
│  ├─ run_tests.gd               # extends SceneTree ヘッドレスランナー
│  └─ test_{board_model,explosion,turn_resolver,generator,fixture_walkthrough}.gd
└─ docs/{implementation-plan,architecture,decisions,playtest-checklist}.md
```

**game_balance.gd(唯一の数値置き場)**: `BOARD_W=7, BOARD_H=7, MINE_COUNT=9, EXPLOSION_CENTER_DAMAGE=4, EXPLOSION_ADJACENT_DAMAGE=2, EXPLOSION_RADIUS_CHEBYSHEV=1, ENEMY_MAX_HP=6, ENEMY_ATTACK=2, ENEMY_COUNTDOWN=3, PLAYER_MAX_HP=10, ACCIDENTAL_MINE_DAMAGE=3, ENEMY_ZONE_MINES=3, GENERATION_MAX_TRIES=100, LONG_PRESS_SEC=0.4`

**ドメインAPI(要点)**:
- `TurnResolver.resolve(state, action) -> Array` (Dictionary イベントの配列)。action = `{type: REVEAL|DETONATE, cell: Vector2i}`。フラグはターン非消費なので resolver を通らず controller→board 直接+`flag_toggled` イベント。
- イベント type 例: `cells_revealed / mine_exploded(accidental: bool) / dud_detonation / enemy_damaged / player_damaged / enemy_died / victory / countdown_changed / enemy_attacked / defeat / flag_toggled / turn_rejected`
- `BoardModel.preview_detonation(cell) -> {cells_in_range, damage_map, enemy_hit: bool, expected_enemy_damage}`(副作用なし、contains_mine 非依存)
- `BattleController`: `tap(cell) / long_press(cell) / confirm_detonation() / cancel_detonation() / retry() / set_mode(mode) / regen_same_seed() / regen_new_seed() / notify_effects_done()`、`is_busy`
- ターン解決順序(handoff §5.8 厳守): 入力確定 → 開放/起爆解決 → 爆発ダメージ → 敵死亡 → 勝利判定(勝利なら終了)→ 敵カウント減 → カウント0なら敵攻撃+リセット → プレイヤー死亡 → 敗北判定 → UI同期(イベント返却)

## 5. GDScript / Godot 実装規約

- ドメイン/テストは `class_name` のグローバル解決に依存せず **`preload()` 定数参照で統一**(fresh clone で `.godot/` キャッシュが無くても headless 実行を決定的にする)。
- preload の層順厳守・循環参照禁止: cell ← board ← state ← resolver(逆参照が必要なら weakref)。RefCounted は循環でリークする。
- 乱数はローカル `RandomNumberGenerator` インスタンス+明示 seed のみ(グローバル `randi()` 禁止)。seed は state に保持し UI 表示。
- 4.3互換構文で書く(typed Dictionary 等 4.4 限定構文を避ける)。
- 汎用イベントバス autoload を作らない。イベント配列は resolver の戻り値のみ。autoload 自体を使わない。
- テストランナー: `extends SceneTree` + `_initialize()`。`assert()` 禁止(失敗メッセージを収集して全件実行し、最後にサマリ表示)。exit code は 0/1。
- **project.godot は手書き**: `config_version=5` 必須。`[rendering] renderer/rendering_method="gl_compatibility"`(+ `renderer/rendering_method.mobile="gl_compatibility"`)、`[display] window/size/viewport_width=720`、`window/size/viewport_height=1280`、`window/stretch/mode="canvas_items"`、`window/handheld/orientation=1`(int)。**UI導入前は `run/main_scene` を設定しない**。`config/icon` は書かない。
- デバッグ機能(スクショ・地雷表示等)は `OS.is_debug_build()` でゲート。
- 警告を放置しない(起動ログ・テストログにエラー/警告ゼロ)。

## 6. 実装順

1. ✅ 環境(Godot 4.4.1)+本計画
2. ドメイン+生成+テスト(UIなし)— 受入: headless テスト全パス exit 0
3. UI接続(application+presentation+scenes)— 受入: テスト依然パス+起動エラーなし+スクショ検証
4. 統合実行確認(固定盤面勝利/敗北、ランダム、同一seed再現、二重ターン防止)
5. ドキュメント(README / architecture / decisions / playtest-checklist)

## 7. テスト方針(handoff §9 全項目 → ファイル対応)

- **test_board_model.gd**: 四隅/辺/中央の隣接数(§3 正解グリッド)、0フラッド連結展開(=11マス)、フラッドはフラグ済みセルを開放しない、フラグ済みセルは reveal 不可、開放済みセルへのフラグ不可・タップ無効、地雷数=9、敵セル安全+開放済み
- **test_generator.gd**: 同一seed→同一配置(複数seed)、地雷数一致、敵セル安全かつ初期開放済み、敵ゾーン地雷=3、初手地雷時の移設で初手安全+ゾーン3維持、上限超過時 fixture フォールバック
- **test_explosion.gd**: 爆心4/隣接2/範囲外0、誘爆なし、起爆済み再起爆不可、意図起爆は自傷なし、誤爆3ダメージ、誤爆でも範囲内の敵にダメージ、dud起爆=安全開放扱い(0ならフラッド)、爆発で隣接セルが開放されない、起爆時フラグ自動除去、detonated セル非インタラクティブ、誤爆セルは revealed+detonated
- **test_turn_resolver.gd**: フラグでターン不変、開放/起爆で+1、1入力でカウント1のみ減、`notify_effects_done()` 前の追加入力拒否、cd0で攻撃+リセット3、敵死亡ターンは攻撃なし、勝敗同時→勝利、HP0敗北、DETONATE は flagged のみ受理、リトライ初期化(盤面・HP・cd・ターン・ログ・同一seed)
- **test_fixture_walkthrough.gd**: §3 の E2E勝利6手ライン+敗北3手ライン(各手の HP/cd/開放数を assert)

すべて UI 非依存。

## 8. 検証コマンド

```bash
# テスト(headless)
~/.local/bin/godot --headless --path . --script res://tests/run_tests.gd
# シーン導入後の初回 import warm-up
~/.local/bin/godot --headless --path . --import
# 起動(WSLg。不安定なら LIBGL_ALWAYS_SOFTWARE=1 / --display-driver x11)
~/.local/bin/godot --path .
# スクショ検証(開発専用、-- 以降が user args)
~/.local/bin/godot --path . --audio-driver Dummy -- --debug-screenshot=/tmp/shot.png --debug-quit-frames=60
```

## 9. 未確定事項・リスク

- WSLg での描画不安定 → `LIBGL_ALWAYS_SOFTWARE=1` フォールバック。不可なら headless テスト+ユーザー目視に切替(§15 峻別報告)。
- handoff §4 `first_reveal_safe: true` は固定盤面に適用しない(仮確定仕様からの変更として最終報告に明示)。
- ゾーン地雷「ちょうど3個」は全ランダム盤面で敵セル数字が常に3になる多様性トレードオフあり(Phase 2 で再検討)。
