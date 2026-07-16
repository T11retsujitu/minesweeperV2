# Asset Spec — ダンジョンテーマ AI生成アセットの仕様と生成プロンプト

> **読者**: (1) 画像生成AIでアセットを作るユーザー (2) 組込・後処理を行う LLM(Claude / Codex)。
> **正本関係**: 座標契約・受け入れ条件の上位規約は `docs/view-spec.md` §2/§6。本書はそれをアセット制作手順に具体化したもの。
> **記載時点**: 2026-07-17(見た目インパクト強化計画 M-0)。

## 0. ワークフロー全体像

```
ユーザー: 画像生成AI で 1024×1024 の絵を生成(§4 のプロンプト使用)
   → assets_src/ に保存(命名は §3 の id と一致させる。例 assets_src/tile_hidden.png)
Claude/Codex: godot --headless --path . --script res://tools/asset_pipeline.gd
                  … クロマキー→縮小→パレット統一→×2拡大→整列
              godot --headless --path . --script res://tools/asset_check.gd
                  … サイズ/透過/シームレス/接地の機械検品
   → assets/textures/ に最終PNGが出力され、ゲームに即反映(コード変更不要)
```

- `assets_src/` は生成原画置き場(`.gdignore` で Godot のインポート対象外)。
- **アートが未着でもゲームは動く**: `asset_pipeline.gd` に `--placeholders` を渡すと manifest 全件のダミーPNG(単色+ラベル)を出力する。以後のアート反復は PNG 差し替えのみ。
- パイプラインの実装言語は **GDScript(Godot headless)**: この環境に Python PIL / ImageMagick が無く sudo 導入も不可のため、既存の Godot ランタイム(`Image` クラス)で完結させる(依存ゼロ・headless テスト可能という利点もある)。

## 1. 共通規約

| 項目 | 規約 | 理由 |
|---|---|---|
| ドット密度 | **44px グリッドで打ち、×2 NEAREST 拡大して納品**(2画面px=1ドット) | 全アセットのドットサイズ統一 |
| footprint | セル = 88×88(view_config.CELL_SIZE_PX)。hidden タイルのみ 88×98(下10px=前面厚み) | view-spec §2 |
| アンカー | **整列はアートデータ側で完結**: 盤面系=キャンバス全面 / キャラ系=下辺中央が足元(最下段4pxは影用余白)。コード側は `draw_texture(tex, Vector2.ZERO)` か足元原点配置のみ | アンカー計算をコードに持ち込まない |
| フィルタ | 表示側は `TEXTURE_FILTER_NEAREST`(コードで設定済み) | ドット絵のにじみ防止 |
| フォーマット | PNG-32(RGBA)。背景のみ PNG-24 可 | |
| パレット | 共通24色(§2)へ remap(パイプラインが自動実行) | 出自の違う生成画像の統一感 |
| 命名 | `assets/textures/{board,chars,bg,ui,fx}/snake_case.png`、フレームは `_f1/_f2` 接尾 | |
| 数字フォント | **AI生成しない**。既成ピクセルフォント Press Start 2P(OFL 1.1、§6)を使用 | グリフ整合=数字可読性最優先(view-spec §6) |

## 2. 共通パレット(dungeon24)

remap 先の24色。`tools/asset_manifest.json` の `palette` が正本(以下は初期値。見た目評価で調整可)。

```
石(寒色):  #0a0a10 #151521 #222234 #33334d #4a4a66 #66678a #8b8ca8 #b8b9cc
木・土:    #2a2018 #4a3623 #6e5230 #97744a
苔・スライム: #3d5a2e #5f8a3d #8fc45c #b3e05e
血・敵:    #5a1f1f #a03030 #d95763
炎・松明・金: #7a3b12 #d97b28 #f2b02c #ffe08a
骨・白:    #f5f2e6
```

明度階層の設計(静止画の焦点設計。M-A §4 と対応): **爆発FX ≫ キャラ > 数字 > フラグ/樽 > hidden タイル > 床 > 背景**。
床と背景は上記パレットの暗い側だけを使うこと(生成プロンプトにも "dark, low contrast" を含めてある)。

## 3. アセット一覧(manifest と 1:1 対応)

| id | 最終px(キャンバス) | 内容 / 整列 | chroma | 優先 |
|---|---|---|---|---|
| `tile_hidden` | **88×98** | 盛り上がった石ブロック。上88pxが上面、下10pxが前面の厚み。左右上端は隣接タイルとシームレス | なし(全面) | 必須 |
| `tile_hidden_b` | 88×98 | 同上の微差分(苔・ヒビ)。盤面に決定的ハッシュで散る | なし | 推奨 |
| `tile_floor` | 88×88 | 掘られた石畳床。**低彩度・低明度**(数字の土台) | なし | 必須 |
| `tile_floor_b` | 88×88 | 床の微差分 | なし | 推奨 |
| `tile_floor_crater` | 88×88 | 起爆済みクレーター床(焦げ+割れ) | なし | 必須 |
| `overlay_flag` | 88×88 | トラップ標識(髑髏の立て札)。タイル上面に置かれた位置で整列 | 緑抜き | 必須 |
| `overlay_barrel` | 88×88 | 導火線付き爆弾樽(フラグ済み表示・debug 地雷表示に縮小流用) | 緑抜き | 必須 |
| `player_idle_f1` / `_f2` | **88×132** | 冒険者(騎士)正面立ち。足元=下辺中央。f2 は呼吸差分 | 緑抜き | 必須 |
| `slime_idle_f1` / `_f2` | **88×96** | スライム。f1=通常 f2=潰れ | 緑抜き | 必須 |
| `bg_dungeon` | 720×1280 | 暗いダンジョン壁+闇+左右に松明の淡い光。**盤面が主役なので全体を暗く** | なし | 必須 |
| `hud_panel` | 96×96(9-patch, margin 24) | 石枠+暗色羊皮紙風パネル | なし | 必須 |
| `hud_button` / `hud_button_pressed` | 96×48(9-patch) | ボタン2態 | なし | 推奨 |
| `icon_mine` / `icon_flag` | 44×44 | HUD カウンタ用アイコン | 緑抜き | 推奨 |
| `fireball_f1..f3` | 176×176 ×3 | 起爆火球(閃光→火球→散り)。**無ければ手続き描画で代替** | 緑抜き | 任意 |
| `smoke_f1..f3` | 96×96 ×3 | 煙 | 緑抜き | 任意 |

## 4. 生成プロンプト集

### 4.1 生成の鉄則

1. **1アセット=1画像**(シート生成はグリッドずれの元。禁止)。1024×1024 で生成(bg のみ縦長)。
2. **透過を当てにしない**: 切り抜きが要るものは「純緑一色の背景(#00FF00)」で生成 → パイプラインがクロマキー抜き。
3. キャラの2フレーム目は、1フレーム目の画像を画像編集(img2img)に渡して「少しだけ潰す/揺らす」差分指示で作ると揃いやすい。
4. 生成物はドットが粗くなくてよい(高精細でOK)。**縮小とパレット統一はパイプラインの仕事**。ただし「pixel art 風」の指示は画作りの方向を揃えるため入れる。

### 4.2 共通スタイルブロック(全プロンプト先頭に付ける)

```
16-bit pixel art style, dark fantasy dungeon theme, 3/4 top-down view
(front face slightly visible), single game asset, centered composition,
no text, no watermark, no border, limited color palette, crisp pixels
```

切り抜きが要るもの(§3 で「緑抜き」)はさらに: `flat solid pure green background (#00FF00), the subject does not contain any green`

### 4.3 個別プロンプト

- **tile_hidden**: `raised stone block tile of a dungeon grid, seen from 3/4 top-down. The top surface fills the upper 90% of the canvas with straight edges touching the left/right/top canvas borders (seamless tileable horizontally), the bottom 10% is the darker front face (thickness) of the block. cool dark blue-gray stone, subtle cracks, slight top-edge highlight` (_b 差分: `+ patches of moss and a hairline crack`)
- **tile_floor**: `excavated dungeon floor tile, dark desaturated cobblestone seen from above, fills the entire canvas, seamless tileable, very low contrast, very dark, no objects` (_b 差分: `+ tiny pebbles and a faint scratch`)
- **tile_floor_crater**: `same dark cobblestone dungeon floor, with a blackened blast crater in the center, charred scorch marks, cracked and broken stones radiating outward, fills the entire canvas`
- **overlay_flag**: `small wooden warning sign post with a painted white skull mark, planted into the ground, slight tilt, dark aged wood, green background`
- **overlay_barrel**: `wooden powder keg barrel with iron bands and a short lit fuse with a tiny orange spark, sitting on the ground, green background`
- **player_idle_f1**: `brave adventurer knight, full body, standing idle facing the camera, small sword and round shield, blue-gray armor with a gold accent, feet at the bottom center of the canvas, green background`(f2: img2img で `same character, breathing idle: shoulders 2% lower, sword tip slightly moved`)
- **slime_idle_f1**: `menacing but charming green slime monster, glossy blob with two dark eyes, full body, sitting on the ground, feet(bottom) at the bottom center, green background`(f2: `same slime, squashed 15% shorter and 10% wider, blinking`)
- **bg_dungeon**: `dark dungeon interior wall background, portrait orientation, large stone bricks fading into darkness, two distant torches casting faint warm orange glow near the left and right edges, heavy vignette, very dark overall, no floor, no characters`(720×1280 か 9:16 で生成)
- **hud_panel**: `square UI frame panel, carved stone border of uniform 25% thickness on all four sides, dark parchment texture in the center, symmetric, suitable for 9-slice scaling`
- **hud_button**: `wide rectangular UI button, carved stone border, dark parchment center, symmetric`(pressed: `same button, pressed state, darker and slightly inset`)
- **icon_mine**: `small round black bomb with a short fuse, icon, green background` / **icon_flag**: `small wooden skull sign icon, green background`
- **fireball_f1..f3**: `explosion fireball sprite, frame 1 of 3: blinding white-yellow flash core / frame 2: orange fireball with dark smoke edges / frame 3: dissipating embers and smoke, green background`

## 5. 後処理パイプライン(tools/、GDScript + Godot headless)

- `tools/asset_manifest.json` — 全アセットの宣言(id / source / target / canvas_px / pixel_grid / anchor: `fill`|`bottom_center` / chroma / seamless_x / nine_patch / remap)。**パレット(§2)もここが正本**。
- `tools/asset_pipeline.gd`(`godot --headless --path . --script res://tools/asset_pipeline.gd -- [--placeholders] [--only <id>]`)— ①クロマキー→アルファ化(色距離閾値つき、原寸で実施) ②内容 trim(fill は skip) ③pixel_grid へ縮小(Image.INTERPOLATE_LANCZOS) ④パレット remap(最近色置換・ディザなし。fx と bg は `remap:false` で免除可) ⑤×2 NEAREST 拡大 ⑥キャンバス整列(anchor 適用)⑦ `assets/textures/` へ出力。`--placeholders` は manifest 全件のダミーPNG(単色+焼き込み文字)生成。
- `tools/asset_check.gd` — サイズ一致 / 緑抜き対象の四隅 alpha=0 / seamless_x タイルの左右端1列の色差閾値 / bottom_center キャラの接地余白(最下段4px) / remap 対象のパレット外色検出、を一括レポート(exit 0/1)。

## 6. フォント(唯一の既成素材)

- **Press Start 2P** — `assets/fonts/PressStart2P-Regular.ttf`
- ライセンス: **SIL Open Font License 1.1**(同梱 `assets/fonts/PressStart2P-OFL.txt`)。Copyright 2012 The Press Start 2P Project Authors (cody@zone38.net)。出所: google/fonts リポジトリ(ofl/pressstart2p)。
- 8px グリッド設計のため、使用サイズは **8の整数倍**(セル数字=48、HUD=16 or 24、フロート=24 等)。数字はセル中心+`draw_string_outline` 黒縁取り。

## 7. 受け入れ条件(view-spec §6 の再掲+機械検品)

1. `python3 tools/asset_check.py` が全項目 PASS
2. 表示側 NEAREST / hidden の下10pxが下行タイルに覆われる(行順描画)/ キャラ足元= entity_anchor
3. **数字可読性最優先**: MIN ズーム(全体表示)でも数字が判読できること(M-A 受入スクショで確認)
4. 正方グリッド維持(アイソメ化禁止 = decisions D34)
