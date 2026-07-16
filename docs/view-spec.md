# View Spec — 盤面描画・カメラ・入力の規約(2026-07-16 フェーズA〜D)

> **読者**: presentation 層を変更する LLM/開発者。ここに書かれた規約(座標アンカー・レイヤ構造・入力経路・カメラ数学)は
> 将来のドット絵アセット差し替え(pv-vision-roadmap Step 2)の前提契約。破る場合は docs/decisions.md に判断を残すこと。

## 1. ノード/レイヤ構造(battle_screen.gd がコード構築)

```
BattleScreen (Control, full-rect, mouse_filter=IGNORE)
├─ BackgroundLayer (CanvasLayer, layer=-1) … 背景 ColorRect(カメラ非追従・IGNORE)
├─ BoardWorld (Node2D) … 盤面ワールド。カメラの影響を受ける唯一の層
│   ├─ GroundLayer (Node2D) … CellNode × W×H(y昇順→x昇順で追加。行順=描画順が 3/4 ビューの重なりを作る)
│   ├─ EntityLayer (Node2D, y_sort_enabled=true) … PlayerToken / EnemyToken(足元 y でソート)
│   ├─ BoardCamera (Camera2D) … camera_rig.gd
│   └─ BoardInput (Node) … board_input.gd(_unhandled_input)
├─ HudLayer (CanvasLayer, layer=1) … HUD/盤面スロット(空スペーサー)/コントロール/ログ
├─ FxLayer (CanvasLayer, layer=2) … fx_layer.gd(ダメージフロート・弾・パーティクル。スクリーン空間)
└─ OverlayLayer (CanvasLayer, layer=3) … preview/help/terminal/toast(モーダルは MOUSE_FILTER_STOP で盤面入力を遮断)
```

- **CanvasLayer 上の要素はカメラに追従しない**。盤面に張り付く表現(セルフラッシュ・ハイライト等)は CellNode/Token 側、
  画面に張り付く表現(フロート・HUD)は FxLayer/HudLayer 側に置く。
- 演出中(`controller.is_busy`)とモーダル表示中は `board_world.set_input_enabled(false)` でタップ/パン/ズームすべて停止。
  スクリーン空間 FX がカメラ移動とズレないのはこのロックが前提。

## 2. 座標規約(view_config.gd が唯一の定義)

| 定数/関数 | 意味 |
|---|---|
| `CELL_SIZE_PX = 88` | セル footprint(論理px)。ワールド座標の唯一の基準 |
| `world_pos(coord)` | セル左上 = `coord * CELL_SIZE_PX`。CellNode.position |
| `cell_center(coord)` | セル中心。数字・フラッシュ・FX 座標問い合わせの基準 |
| `entity_anchor(coord)` | **footprint 下辺中央(足元)**。トークン/キャラスプライトの origin |
| `CELL_INSET_PX = 2` | タイル描画の内側インセット(旧グリッド4px間隔の代替。テクスチャ時は 0 化検討) |
| `TILE_THICKNESS_PX = 10` | 未開放タイルの前面(下辺)の厚み。3/4 ビューの立体感 |
| `TOKEN_HEIGHT_PX = 104` | トークンの高さ。セル(88)より背が高く、頭が 1 つ上のセルに重なる |

**3/4 見下ろしビューの重なり規則**(ドット絵差し替え時もこの規則に載せる):

1. タイルは footprint 内に描き、未開放(盛り上がった)タイルのみ下方向に厚みバンドをはみ出す。
   GroundLayer の行順追加により「下の行のタイルが上の行の厚みを覆う」が自動成立。開放済みセルは厚みなし(掘られた床)。
2. キャラは `entity_anchor`(足元)に立ち、上方向に伸びる。EntityLayer の Y ソートで
   「下の行のキャラが上の行のタイル上部・キャラより手前」が自動成立。
3. 数字・ハイライト・縄張り・プレビューは CellNode(GroundLayer)側 = 常にキャラの背後。

## 3. カメラ(camera_rig.gd + camera_math.gd)

- 状態は `view_center`(盤面スロット中心に映る world 点)と `zoom_scalar` の2つ。`Camera2D.position` は毎フレームではなく変更時に導出:
  `position = view_center - (slot_center - viewport_center) / zoom_scalar`
- 数学は `camera_math.gd` の**純関数**(fit_zoom / clamp_center / zoom_at_point / pan_center)に分離済み。
  **ヘッドレステスト対象**(tests/test_camera_math.gd)。Node/Viewport 参照をここに持ち込まない。
- すべて**論理座標(720×1280)**で閉じる。`DisplayServer` 系 API 禁止。stretch=canvas_items の倍率は
  `get_global_transform_with_canvas()` 経由で自動吸収される。
- ズーム範囲 `MIN_ZOOM=0.5`〜`MAX_ZOOM=2.0`、ホイール1段 `ZOOM_WHEEL_STEP=1.1`、フィット上限 `FIT_MAX_ZOOM=1.0`。
- 初期表示: `fit_zoom ≥ MIN_ZOOM` なら全体フィット(7×7→zoom1.0 / 12×12→zoom≈0.61)。下回る盤面はフォーカス中心 zoom=1.0。
- **refit は (a)初期レイアウト後 (b)board_slot.resized (c)state_reset のみ**。
  `debug_cell_canvas_position` 等の座標問い合わせに refit 副作用を入れてはならない(ユーザーのパン/ズーム状態を破壊する)。
- shake は `Camera2D.offset` の乱数振動(view_center と直交・共存可)。`viewport.canvas_transform` 直叩きは禁止(Camera2D が毎フレーム上書きするため)。

## 4. 入力(board_input.gd)

- 盤面入力は **`_unhandled_input`** で受ける。GUI(HUD ボタン・モーダル)が消費した残りだけが届く。
  したがって**盤面領域に重なる非対話 Control は必ず `mouse_filter=IGNORE`**(Main ルート/BattleScreen ルート/背景/HUD root VBox/盤面スロット)。
  STOP の Control が 1 枚でも被ると盤面クリックが死ぬ(退行前科: 2d34a2a、フェーズAで Main の指定漏れを検出)。
- ジェスチャ状態機械: IDLE → PRESSED(押下時にセル座標を確定)→
  { 累積移動 > `DRAG_TAP_CANCEL_PX`(=12, game_balance)→ PANNING / `LONG_PRESS_SEC` 経過 → long_press → CONSUMED / release → tap / 2本目タッチ → PINCHING }
- パンは grab 操作感(盤面が指に追従)。ピンチは2点距離比+中点アンカー、ホイールはマウス位置アンカー。すべてクランプ経由。
- 右クリック = 即 long_press。`event.device == InputEvent.DEVICE_ID_EMULATION` のマウスイベントは無視(タッチ二重発火防止)。
- セル判定は `board_world.get_global_transform_with_canvas().affine_inverse()` によるスクリーン→ワールド変換(カメラ状態を自動反映)。

## 5. 検証プロトコル(実入力必須)

- 入力検証は `click:` `rclick:` `presshold:` `drag:` `wheel:`(viewport.push_input 実経路)で行う。`tap:`/`flag:` はドメイン検証専用。
- `zoomstate` でカメラ状態を stdout に出せる。パン/ズーム後に `click:` が的中することが座標変換の回帰ゲート。
- 詳細コマンドは docs/llm-status.md §9。

## 6. Step 2(ドット絵アセット導入)の受け入れ条件

- スプライトは `texture_filter = TEXTURE_FILTER_NEAREST`(ドット絵のにじみ防止)。
- タイル: hidden=盛り上がりタイル(前面の厚みを絵に含める、footprint 88px + 下部厚み)/ revealed=床タイル。
  `CELL_INSET_PX` は 0 にしてシームレスに敷き詰め可(タイル境界は絵で表現)。
- キャラ: 足元を `entity_anchor` に合わせ、高さはセル超過可(Y ソートが重なりを処理)。
- 非整数ズームはドット絵が歪むため、ズーム段階の離散化(例 0.5/0.75/1.0/1.5/2.0)を導入検討(view_config にステップ表を持たせる)。
- 数字の可読性が最優先(3/4 ビューでもグリッドは正方形のまま。アイソメ化はしない — decisions D34)。
