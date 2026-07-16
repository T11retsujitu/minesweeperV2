# CLAUDE.md

**最初に `docs/llm-status.md` を読むこと**(現状・課題・残タスク・不変条件・再開手順のすべてがそこにある)。

要点だけ:

- 体制(ユーザー指定): Claude = 設計/検証/オーケストレーション。**実コーディングは Codex MCP**(`mcp__codex__codex`)に依頼する。基本Auto進行
- テスト: `~/.local/bin/godot --headless --path . --script res://tests/run_tests.gd` — 501件・exit 0 が正常。domain/generation 変更後は必須
- fixture `phase1_core_demo` の座標は変更禁止(検証済みオラクル)。数値調整は `scripts/config/game_balance.gd` のみ
- git: push 禁止。マイルストーン毎にローカルコミット
- コード変更後は Windows プレイ用コピーの rsync 同期が必要(コマンドは llm-status.md §2)
