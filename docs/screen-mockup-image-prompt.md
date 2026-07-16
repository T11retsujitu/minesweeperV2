# スマホ縦画面プレイ画面 — 画像生成用プロンプト資料

> **目的**: 本プロジェクト(マインスイーパー・ローグライト、Godot 4.4.1 / 720×1280縦画面)の**現状の**プレイ画面を、
> 画像生成LLMに渡して「イメージ図」として描かせるための資料。
> **記載時点**: 2026-07-16(Phase 2 描画基盤刷新フェーズA〜D 完了時点)。コード(`scripts/presentation/*.gd`, `scripts/config/game_balance.gd`)から起こしたもので、推測・演出的誇張は含まない。
>
> **重要な前提**: これは完成品のゲームアートではない。ドット絵アセット導入(pv-vision-roadmap Step 2)は**未着手**であり、
> 現状の見た目は「平面ベクター・単色塗り・幾何形状のプレースホルダ」で構成された 3/4 見下ろし(トップダウンをやや斜めに見た)UIモックアップである。
> 画像生成時は「完成度の高いファンタジーRPGアート」ではなく「ダークテーマの機能的なモバイルゲームUIプロトタイプのスクリーンショット」として描かせること。

---

## 1. 画面全体仕様

- **アスペクト比**: 720×1280(縦長 9:16)、スマートフォン縦持ち画面いっぱいのゲームUI
- **背景色**: ほぼ黒に近い暗いティール `#141a1c` 相当(RGB 0.08, 0.10, 0.11)
- **レイアウト**: 上から下へパネルが縦積み(左右マージン約20px)。上から順に:
  1. **HUDパネル**(高さ約184px、暗い青緑 `#212c30` 相当)
  2. **盤面エリア**(残りの大部分、画面の主役)
  3. **コントロールパネル**(高さ約112px、`#1e262b` 相当)
  4. **アクションログパネル**(高さ約190px、最も暗い `#171e21` 相当、スクロール可能なテキストリスト)

全体として「ダークモードの縦型モバイルゲームUI」の質感(角丸パネル、フラットな塗り、装飾少なめ)。

---

## 2. HUDパネル(上部)

2列グリッドで構成:

- **左列: PLAYER HPバー** — 小さい灰白色ラベル "PLAYER"(12px)の下に、暗い背景 `#0a0f11` のバー(高さ22px)、緑色 `#3dc770` 相当の塗りが現在HP割合ぶん埋まる(最大10)。バー中央に白文字+黒縁取りで "7/10" のような数値。
- **右列: ENEMY HPバー** — 同様の見た目で塗り色は赤 `#dc3340` 相当(最大6)。
- その下に小さな灰色/白テキストラベル(14px)が並ぶ:
  - "Enemy countdown: N" または縄張り外なら "Countdown: N (paused)"
  - 敵の攻撃予告テキスト
  - "Mines: N"(残り未フラグの地雷数)
  - "Flags: N"(または回収フェーズ中は "Board: n/N")
  - "Seed: ..."
  - "Turn: N"
  - "Input: ..."
  - ステータス行(通常時は "Ready")

---

## 3. 盤面エリア(画面の主役・中央〜下寄り大部分)

- **視点**: 3/4見下ろし(バードビューをやや斜めに傾けた視点。アイソメではなく、グリッドは正方形のまま)
- **グリッド**: 正方形タイルが並ぶ盤面。1マス88px相当。標準戦は7×7、ランダム戦は12×12(カメラがズームアウトして盤面全体をフィット)
- **タイルの状態別の見た目**:
  - **未開放タイル**: 鋼青灰色 `#3a5766` 相当の塗り、明るい青灰色の枠線、角丸(約5px)、柔らかい落ち影。**タイル下辺に厚みバンド(暗い色、約10px)があり、盤面から一段盛り上がったブロックのような立体感**(掘り出す前の地面ブロックのイメージ)
  - **開放済みタイル**: 厚みなし・フラットな塗り(掘られた床)。色は隣接地雷数によるヒートマップ(0=淡い灰緑 → 1〜2=黄緑〜黄土色 → 3〜4=オレンジ → 5以上=深い赤茶)。中央に太字の数字、数字の色は 1=青、2=緑、3=赤、4=紫、5=茶色、6以上=ほぼ黒
  - **フラグ済みタイル**: 暗い赤 `#7a2929` 相当の塗り+金色の枠線、厚みバンドあり。上に小さな**漫画風の爆弾アイコン**(ほぼ黒い丸い本体、左上に青白いハイライトの弧、右上へカーブする茶色い導火線、先端にオレンジ色の火花の点)を描画
  - **起爆済み(爆発跡)タイル**: フラット・暗い炭灰色の塗り、ほぼ黒の枠線、中央に太い赤色の "X"
  - **行動可能ハイライト(半透明の色面+明るい2px枠線)**:
    - 移動可能セル: 半透明シアン/ティール塗り+明るいシアンの枠
    - 開放可能セル: 半透明ゴールド/黄色塗り+明るい金色の枠
    - 攻撃(bump)可能セル(隣接する敵): 半透明の赤塗り+明るい赤の枠
  - **縄張り(territory)ティント**: プレイヤー中心の半径2マスの範囲全体に、非常に薄い(10%程度)赤の半透明オーバーレイ。行動可能ハイライトより控えめで、プレイヤー周囲がうっすら赤みがかって見える程度

---

## 4. キャラクター(盤面上に立つトークン)

- **プレイヤートークン**: セルの足元(タイル下辺中央)を基準に、タイルより背が高く(約104px)上へ伸びる。**顔のない人型/ロボット風シルエット**——白い輪郭線+ティールシアンの塗り、肩から先細りになる胴体形状、胴体中腹に薄い白の横ラインベルト、足元に柔らかい楕円影。加えて足元付近に**シアンのひし形マーカー**(白い輪郭線つき、光って見える)があり「これがプレイヤー」を示す
- **敵トークン**: プレイヤーよりさらに大きく背が高いシルエット。ほぼ黒い輪郭線+暗い深紅/マルーンの塗り、四角みのある「頭」部分に白く光る目(黒い瞳)が2つ、水平な暗い口のライン。同じく足元を基準に立ち、柔らかい落ち影。**頭上に小さな正方形バッジ**が浮いており、白文字+黒縁取りでカウントダウン数字(例: "3" "2")を表示。カウントダウンが残り1になると赤がより強くなり "1!" と表示されて明滅する(攻撃直前の警告)
- 両キャラクターとも**単純な平面ベクター・単色塗りのプレースホルダ形状**(まだドット絵スプライトではない)。盤上に立つ紙製ミニチュア駒のような質感で、3/4視点のトップダウンに自然に馴染む見た目

---

## 5. 演出・エフェクト(任意・静止画に1〜2個含めると良い)

- セルから浮かび上がって消えていく色付きテキスト: オレンジ "-2 ENEMY ATK"、オレンジ寄り "-3 MINE!"、暖色の黄色 "-N"(敵への与ダメージ)、シアン寄りの "DEFUSE"
- 敵撃破時: 金色のパーティクルが放射状に飛び散る演出+ "ENEMY DOWN!" の金文字
- 起爆時: 中心のパーティクル爆発+外周リング状のパーティクル(オレンジ/赤)、画面の軽い明滅・揺れ
- 静止画としての説得力を保つため、上記は最大1〜2要素に留める(例: 起爆直後で1つだけダメージ数字が浮いている、敵バッジが光っている、など)

---

## 6. コントロールパネル(盤面の下)

小さめの角丸ボタンが横並び(暗いグレー/ブルー、白文字): "Fixed" "Random" "Same Seed" "New Seed" "Retry" "Help"。("Finish" ボタンは特定フェーズのみ表示、通常は非表示。デバッグビルドのみ小さな "Show Mines" チェックボックスあり)

---

## 7. アクションログパネル(最下部)

暗い背景のスクロール可能なリスト。小さめ(14px)の白〜灰色の左寄せテキストが複数行、簡潔なログ("Revealed (3,4)"、"Enemy attacked for 2" 等の英語ログ行のイメージ)。

---

## 8. 全体的な作風の指定

- これは**完成品のゲームアートではなく「機能的なUIプロトタイプのスクリーンショット」**。平面的なベクター図形、単色塗り、細い枠線、グラデーションは最小限(ヒートマップとバッジの光る表現程度)。テクスチャなし・ドット絵スプライトなし(将来予定だが未実装)
- モバイルゲームUIのスクリーンショットとして描く: シャープな矩形パネル、小さめのサンセリフUIフォント、全体を通してダークテーマ、絵画的・写実的にせず、すべてフラットシェーディングで統一
- **配色まとめ**: 背景=ほぼ黒のティール/ 未開放タイル=鋼青灰色/ 開放タイル=ヒートマップ(灰緑→黄→オレンジ→赤)/ シアン=プレイヤー・移動可能/ 金・黄=開放可能・フラグ/ 赤=敵・危険・攻撃可能/ 緑=プレイヤーHP/ 赤=敵HP

---

## 9. 具体的に描く盤面構図(推奨コンポジション)

- 7×7盤面、左上寄りは開放済みで 1〜3 の色分けされた数字が複数見える。右下寄りに未開放の鋼青灰色タイルがまとまって残る。中央付近にフラグ済み(爆弾アイコン)タイルが2つ。上部に起爆済み(赤い X)タイルが1つ
- プレイヤートークンは中央やや左の開放済みタイルに立ち、ひし形マーカーが光る。隣接する2〜3タイルにシアン(移動可能)・金(開放可能)のハイライト枠。プレイヤー周囲5×5相当にうっすら赤い縄張りティント
- 敵トークンはプレイヤーから2マス右、頭上バッジに "2"。プレイヤーと敵の間に赤くハイライトされた攻撃可能(bump)タイルが1つ
- HUD: PLAYERバーは緑で約7/10、ENEMYバーは赤で約4/6、"Enemy countdown: 2"、"Mines: 6"、"Turn: 5"、ステータス "Ready"
- 起爆済みタイル付近から小さくオレンジの "-3 MINE!" というダメージ数字が浮いている(直前に起爆したことを示唆)

---

## 10. そのまま画像生成に貼り付けられる英語プロンプト(まとめ)

```
A screenshot mockup of a dark-themed mobile roguelite minesweeper game, portrait phone screen (720x1280, 9:16 aspect ratio). This is an early functional UI prototype, NOT finished game art — flat vector shapes, solid flat colors, thin borders, minimal gradients, no textures, no pixel-art sprites. Near-black teal background throughout.

Layout from top to bottom: (1) a dark blue-green HUD panel with two HP bars side by side — left "PLAYER" bar filled green ~70%, right "ENEMY" bar filled red ~65%, each showing white outlined numbers like "7/10" and "4/6"; below them small gray UI text lines reading "Enemy countdown: 2", "Mines: 6", "Turn: 5", "Ready". (2) A large 3/4 top-down (bird's-eye, slightly tilted, NOT isometric) grid game board of square tiles, 7x7 grid: unrevealed tiles are steel blue-grey raised blocks with a darker thickness band on their bottom edge (like a beveled puzzle block popping up); revealed tiles are flat "dug floor" tiles colored on a heatmap from pale sage-green (few adjacent mines) to orange to deep red (many adjacent mines), each showing a bold colored number (1=blue, 2=green, 3=red, 4=purple); two tiles show a flag with a small cartoon bomb icon (black round bomb, blue-white highlight, curved brown fuse, orange spark); one tile has a bold red "X" mark (a detonated cell). Some tiles glow with a translucent highlight and bright border: cyan for movable tiles, gold/yellow for revealable tiles, red for an attackable tile next to the enemy. A faint translucent red tint covers a 5x5 patch of tiles around the player (territory zone). Standing on the board: a simple flat-shaded humanoid token in teal-cyan with a white outline and a glowing cyan diamond marker at its feet (the player), and nearby a taller, darker crimson humanoid token with glowing white eyes and a small square badge above its head showing the number "2" in white on red (the enemy, telegraphing an attack countdown). Faint drop shadows under both tokens. One small orange floating damage text "-3 MINE!" rising near the detonated tile. (3) Below the board, a row of small flat rounded rectangular buttons with white text: "Fixed", "Random", "Same Seed", "New Seed", "Retry", "Help". (4) At the bottom, a dark scrollable action-log panel with several lines of small plain white/gray text like terse game log entries.

Overall mood: functional, dark-themed, flat-shaded UI mockup for a phone game prototype — crisp rectangular panels, small sans-serif UI font, no painterly or photorealistic rendering.
```
