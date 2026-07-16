# Minesweeper Roguelite — Phase 2 戦闘プロトタイプ

マインスイーパーの推理で地雷を特定し、その地雷を**攻撃資源として起爆**して敵を倒す短時間ローグライトの戦闘垂直スライス。

検証したい核仮説: **「数字を読んで特定した地雷を、敵への攻撃として起爆する行為そのものが気持ちよいか」**

## 動作環境

- Godot **4.4.1 stable**(このリポジトリの開発では `~/.local/bin/godot` に配置)
- 開発確認環境: WSL2 (Ubuntu) + WSLg。Windows/macOS/Linux のデスクトップでも動作する想定

## 起動

```bash
godot --path .
# WSLg で描画が不安定な場合
LIBGL_ALWAYS_SOFTWARE=1 godot --path . --display-driver x11
```

起動するとデフォルトで**固定盤面**(`phase1_core_demo`、7×7)が読み込まれる。Random ボタンで **12×12 のランダム盤面**(カメラでパン/ズーム)に切り替え。

## 操作方法(現行: 盤上アバタールール)

あなた(菱形マーカー)は盤上に立っている。ルールの詳細と設計意図は `docs/game-design.md` 参照。

| 操作 | 効果 |
|------|------|
| 左クリック: 隣接する未開放セル(黄ハイライト) | 開放(1ターン)。0ならフラッド連鎖 |
| 左クリック: 隣接する開放済みセル(青緑ハイライト) | **移動**(1ターン) |
| 左クリック: 隣接する敵セル(赤ハイライト) | **bump攻撃**(1ターン)。敵に1、敵が生き残ると反撃2 |
| 左クリック: フラグ済みセル(どこでも) | **起爆確認**を開く(起爆は遠隔可) |
| 右クリック または 長押し(0.4秒) | フラグの設置・解除(任意セル、ターン非消費) |
| 起爆確認の Detonate | 起爆(1ターン)。爆心4・周囲2ダメージの3×3爆発 |
| 起爆確認の Defuse(隣接時のみ表示) | **地雷除去**(1ターン)。自傷なしで敵に2、周囲の数字が再計算される |
| ドラッグ / ホイール | 盤面のパン / ズーム(12×12 ランダム盤面用) |

- 開放・移動・起爆・bump・除去はターンを消費する。**敵カウントダウンは縄張り(敵周囲の色塗り3×3)の中にいるときだけ進み**、0になると敵が攻撃(2ダメージ)してカウントは3に戻る。縄張りの外ではカウント停止(paused 表示)
- **爆風は自分にも当たる**(隣接2ダメージ)。起爆前に爆風圏から離れること
- 地雷を直接開くと**誤爆**: 自分に3ダメージ(範囲内の敵にも通常ダメージ)。誤爆跡は歩けない
- フラグ済みの安全セルを起爆すると **dud**(不発): ターンだけ消費して当該セルが遠隔開放される
- **敵HP(6)を0にすると回収フェーズ**: カウントダウンが止まり、盤面を開け続けられる。全安全セル開放で **PERFECT CLEAR**、Finish ボタンでいつでも終了(統計リザルト表示)。プレイヤーHP(10)が0以下で敗北

### 画面下部のボタン

- **Fixed / Random**: 固定盤面とシード付きランダム盤面の切り替え
- **Same Seed**: 同じシードで再生成(再現) / **New Seed**: 新しいシードで生成
- **Retry**: 同一盤面でやり直し
- **Finish**(回収フェーズ中のみ表示): 回収を切り上げて勝利を確定(リザルト表示)
- **Help**: 操作説明
- **Show Mines**(デバッグビルドのみ): 地雷位置を表示

## テスト

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

1558件のドメイン・生成・カメラ数学・E2Eテストが実行され、全件パスで exit code 0。UI描画には依存しない。

## デバッグ実行(開発ビルドのみ)

```bash
# 起動 → 操作列を自動実行 → スクリーンショット保存 → 終了
godot --path . --audio-driver Dummy -- \
  --debug-actions="flag:1,1;tap:1,1;confirm;wait:30" \
  --debug-screenshot=/tmp/shot.png --debug-quit-frames=60
```

`--debug-actions` の文法(`;`区切り): `tap:x,y` / `flag:x,y` / `click:x,y` / `rclick:x,y` / `presshold:x,y` / `confirm` / `cancel` / `finish` / `retry` / `wait:N` / `mode:fixed` / `mode:random` / `sameseed` / `newseed` / `help` / `mines:on|off` / `drag:x0,y0,x1,y1` / `wheel:up|down@x,y` / `zoomstate`

## プロジェクト構成

```
scripts/config/       全ゲーム数値(game_balance.gd に一元化)
scripts/domain/       純粋なゲームルール(Node/UI非依存、RefCountedのみ)
scripts/generation/   固定盤面データ + シード付きランダム生成
scripts/application/  BattleController(入力ロック・意図→ドメイン変換)
scripts/presentation/ 描画と入力通知のみ(ルール判定なし)
tests/                ヘッドレステストランナー + テスト群
docs/                 実装計画・アーキテクチャ・設計判断・プレイテスト
```

詳細は [docs/architecture.md](docs/architecture.md)、仕様裁定の理由は [docs/decisions.md](docs/decisions.md) を参照。

## 既知の制約・注意

- 現行スコープ: ラン連結・遺物・ショップ・セーブ・音・本番アートは**意図的に未実装**(handoff §3。次候補はドット絵アセット導入=docs/pv-vision-roadmap.md Step 2)
- 固定盤面では初手安全保証(first_reveal_safe)を適用しない(盤面が固定のため。ランダム盤面のみ初手地雷を自動移設)
- 通常プレイでは敵は安全セル上に固定のため、爆心4ダメージは実質発生しない(隣接2ダメージで削るか、bump/除去を使う)。ドメインは爆心ダメージを実装済みでテストで検証している
- 数字は盤面生成時に固定され、**起爆**で地雷が消費されても再計算されない(**地雷除去(Defuse)のみ再計算される** — 除去は盤面が読み直せるのが利点)
- WSLg 実行時に V-Sync 関連の WARNING が1件出る(グラフィックドライバ制約。ゲーム動作に影響なし)
- 手動プレイテスト(handoff §13)は未実施 → [docs/playtest-checklist.md](docs/playtest-checklist.md)
