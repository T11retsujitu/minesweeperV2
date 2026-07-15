# LLM向けプロジェクト状態ドキュメント

> **読者**: 本プロジェクトを引き継ぐLLM(Claude / Codex)。人間向け説明は README.md。
> **目的**: 最短で「何ができていて・何ができておらず・何が課題で・次に何をするか」を正確に把握させる。
> **記載時点**: 2026-07-16, HEAD = `b8060c4`(課題1記録コミット)。**このファイルは状態が変わったら必ず更新すること。**

## 1. プロジェクト要約

- **What**: マインスイーパーの地雷を「敵への攻撃資源」として起爆する短時間ローグライトの戦闘プロトタイプ。Godot 4.4.1 / GDScript / 720×1280縦画面 / gl_compatibility。
- **核仮説(未判定)**: 数字を読んで特定した地雷を敵への攻撃として起爆する行為そのものが気持ちよいか。
- **現フェーズ**: Phase 1(戦闘垂直スライス)= **実装・自動検証・実行確認まで完了**。手動プレイテスト(体験評価)が進行中。
- **体制(ユーザー指定・変更不可)**: Claude = 設計者/オーケストレーター/検証者。**実コーディングは Codex MCP**(`mcp__codex__codex` / `codex-reply`)に依頼する。ユーザーは基本Auto進行(確認質問は最小限)を希望。

## 2. 環境ファクト

| 項目 | 値 |
|------|-----|
| Godot (WSL) | `~/.local/bin/godot`(4.4.1.stable.official)|
| 実行環境 | WSL2 Ubuntu + WSLg(DISPLAY=:0。ウィンドウ実行・スクショ検証可)|
| テスト | `~/.local/bin/godot --headless --path . --script res://tests/run_tests.gd` → **230 passed / exit 0 が正常** |
| Windowsテストプレイ | `C:\Users\a\minesweeperV2-play\`(プレイ用コピー)+ `C:\Users\a\Godot\Godot_v4.4.1-stable_win64.exe` + デスクトップ `Play_Minesweeper.bat` |
| Windowsコピー同期 | `rsync -a --delete --exclude='.git' --exclude='.godot' --exclude='*.md' --exclude='docs' ~/src/minesweeperV2/ /mnt/c/Users/a/minesweeperV2-play/` — **コード変更のたびに必要(自動同期なし)** |
| Git | ブランチ main のみ。remote(origin)は空。**push 禁止**。マイルストーン毎にローカルコミット、`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 付与 |
| Codex サンドボックス | workspace-write / approval-policy never。**ウィンドウ実行不可** → 視覚検証は Claude が WSLg で行う |

## 3. できている部分(検証方法付き)

- **ドメイン層完全動作**: 盤面/数字/開放/0フラッド/フラグ/起爆/dud/誤爆/爆発ダメージ(爆心4・隣接2)/敵カウントダウン攻撃/勝敗/リトライ — handoff §9 必須テスト全項目+E2E(勝利6手/敗北3手ライン)= **テスト230件で検証**
- **生成**: 固定盤面 `phase1_core_demo`(論理攻略可能性をソルバーで証明済み)/ シード付きランダム(敵ゾーン地雷ちょうど3個・敵内側5×5・初手安全移設・上限100+fixtureフォールバック)= テスト+スクショで検証
- **UI全画面**: HUD(HP/カウントダウン/シード/ターン/入力モード)/ 盤面 / 起爆プレビュー / 勝敗オーバーレイ / Help / アクションログ / デバッグ(Show Mines)= **WSLgスクショ8枚で目視検証**(boot/preview/after_detonate/victory/defeat/random_mines/help/real_input)
- **実マウス入力**: 左クリック開放・右クリック/長押しフラグ・起爆確認 = 合成イベント(`click:x,y`)を実入力パイプラインに流して検証(修正 `2d34a2a` 参照)
- **handoff §12 完了条件**: 機能16項目・品質7項目・検証可能性3項目すべて充足
- **ドキュメント**: README / implementation-plan / architecture / decisions(D1〜D21)/ playtest-checklist 完備

## 4. できていない部分

### 4a. 意図的スコープ外(handoff §3。**先回り実装禁止**)
ラン連結 / ルート選択 / 遺物 / 戦闘後3択 / 複数キャラ / 通貨・ショップ / 恒久成長 / ストーリー / セーブ / 広告・課金 / オンライン / ランキング / 本番アート・音 / 完全ソルバー / 複数マスボス / Android実機対応

→ Phase 2〜5 バックログは handoff §16。**着手条件 = Phase 1 プレイテストが肯定的であること(未判定)**

### 4b. Phase 1 内で未完了
- **手動プレイテスト(handoff §13 の10項目)** — 1項目相当の初回フィードバックのみ。核仮説の判定が最重要未完了タスク
- 課題1(下記)の対応判断

## 5. 既存の課題(open)

- **課題1: 敗北条件・被ダメージ原因が分かりにくい**(2026-07-16 ユーザー報告)
  - 症状: プレイヤーHPがなぜ減ったのか分からない。「敵と遭遇したのか?」という混乱
  - 原因分析: プレイヤーが盤面上に不在(空間的手掛かりなし)+ 攻撃演出が弱く因果(カウント0→攻撃→HP減)が画面上で分散
  - 対応候補4案は docs/playtest-checklist.md「発見された課題」参照(候補1〜3 = presentation層のみで安価、候補4 = Phase 2設計判断)
  - **状態: ユーザー指示により記録のみ・対応保留**

### 恒常的な注意(バグではない)
- WSLg実行時に V-Sync WARNING 1件(ドライバ制約・無害)
- ランダム盤面の敵セル数字は常に「3」(decisions.md D8 のトレードオフ)
- 爆心4ダメージは通常プレイで発生しない(敵は安全セル固定。D19)
- first_reveal_safe は固定盤面に適用されない(D10)

## 6. 残タスク(優先順)

1. **手動プレイテスト継続** — docs/playtest-checklist.md の10項目を記録。特に「起爆の手応え(核仮説)」
2. 課題1の対応判断(ユーザーの指示待ち。提案するなら候補1〜3の演出強化が安価)
3. プレイテスト結果に応じた `game_balance.gd` の数値調整(全数値がここに一元化されている)
4. 判定が肯定的なら Phase 2 計画(敵2〜3種・敵移動・装甲・地雷除去・行動予告改善)
5. (運用)コード変更時: テスト実行 → Windowsコピー rsync → 必要なら本ファイル更新

## 7. 不変条件(破る前にユーザー/設計判断が必要)

- **fixture `phase1_core_demo` の座標は変更禁止**(ソルバー検証済みの正解。正解グリッドとE2Eラインは docs/implementation-plan.md §3 = テストのオラクル)
- レイヤ依存方向: presentation → application → domain → config。domain は RefCounted のみ・Node/UI非依存
- `class_name` 不使用(preload統一)/ autoload不使用 / 汎用イベントバス禁止
- 全ゲーム数値は `scripts/config/game_balance.gd` のみ(直書き禁止)
- ターン解決は handoff §5.8 の順序厳守(勝利時は敵カウント減以降スキップ)
- 隣接計算は固定8近傍(`ADJACENCY_RADIUS`)、爆発半径(`EXPLOSION_RADIUS_CHEBYSHEV`)と混同しない(D15)
- テスト230件が domain/generation の門番 — 変更後は必ず実行

## 8. ドキュメントマップ

| ファイル | 役割 |
|----------|------|
| `claude_code_initial_handoff_minesweeper_roguelite.md` | 要求仕様の正本(§5ルール・§9テスト・§12完了条件・§16バックログ)|
| `docs/implementation-plan.md` | 拘束仕様(設計判断21・**fixture正解グリッド**・API・実装規約)|
| `docs/decisions.md` | 判断記録 D1〜D21(理由と変更可能性)|
| `docs/architecture.md` | レイヤ構造・イベントカタログ・状態の正本 |
| `docs/playtest-checklist.md` | §13の10項目+**発見された課題リスト**(課題1あり)|
| `docs/llm-status.md` | 本ファイル。**状態変化時に更新すること** |
| `README.md` | 人間向け(起動・操作・テスト)|

## 9. オーケストレーション手順(セッション再開時のプロトコル)

1. コードを書くタスクは Codex MCP へ。プロンプトに: 参照ドキュメント指定+該当仕様の埋め込み / 変更禁止領域の明示(domain等を凍結する場合)/ 受入コマンド / 「提出前に自分でテスト実行して exit 0 確認」を含める。Phase 1 のスレッドは完了済み — 新タスクは新スレッドで開始してよい(このファイルと implementation-plan を読ませれば文脈は足りる)
2. Claude 検証ゲート: テスト独立実行 → 変更ファイルを Read してレビュー(不変条件チェック)→ UI変更なら WSLg スクショ検証
3. スクショ/操作検証: `~/.local/bin/godot --path . --audio-driver Dummy -- --debug-actions="..." --debug-screenshot=<path> --debug-quit-frames=60`
   - コマンド: `tap:x,y` `flag:x,y`(controller直呼び)/ `click:x,y` `rclick:x,y`(実入力パイプライン)/ `confirm` `cancel` `retry` `wait:N` `mode:fixed|random` `sameseed` `newseed` `help` `mines:on|off`
   - 入力バグの検証は必ず `click:`/`rclick:`(実経路)を使う。`tap:` はドメイン検証用(過去に `tap:` のみで検証して実入力バグを見逃した実績あり → 修正 `2d34a2a`)
4. マイルストーン毎にコミット(push禁止)→ Windowsコピー rsync → 本ファイル更新
