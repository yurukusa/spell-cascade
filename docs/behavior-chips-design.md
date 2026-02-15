# Behavior Chips 設計メモ

## コンセプト（Codex + ぐらすインスピレーション）
「操作機序そのものが装備」— プレイヤーの行動パターンがドロップ/装備品になる。
ラカトニア（放置モード）を「怠惰」ではなく「知識=力」として設計。

## WHEN <Trigger> DO <Action> フォーマット
3スロット。各スロットに1チップ。

### レアリティ設計
- **Common**: Action（AimNearest, AimInMoveDir, MoveToSafety, BasicAttack）
- **Uncommon**: Trigger（HPBelow, EnemyInRange, OnKill, CooldownReady）
- **Rare+**: Detector（StatusDetect, EnemyTypeDetect, BulletDensity, SafeZoneDetect）

## 10→3→1 分析: 初期実装チップ候補

### 10候補
1. AimNearest — 最寄り敵に狙いを定める（現在のデフォルト動作）
2. AimInMoveDir — 移動方向に撃つ（現在のWASD aiming）
3. AimWeakest — HP最小の敵を優先
4. AimFarthest — 一番遠い敵（スナイパー的）
5. SpreadOnKill — キル時に全方向拡散
6. RetargetOnHit — 命中後に別ターゲットへ切り替え
7. OrbitPattern — プレイヤー周囲を周回する弾道
8. FleeWhenLow — HP低下時に敵から離れる自動移動
9. FocusFire — 同じ敵を集中攻撃
10. ChaoticAim — ランダム方向（低レアだが面白い）

### Top 3（ゲームプレイ差が最大 × 実装コスト最小）
1. **AimNearest** (Common) — 現行動作をチップ化。デフォルト装備。実装コスト≒0
2. **AimWeakest** (Uncommon) — ターゲット選択ロジック1行変更。効率プレイvs安全プレイの判断
3. **SpreadOnKill** (Rare) — キルトリガー+全方向拡散。連鎖の快感。PoE的「画面が光る」瞬間

### 選定理由
- AimNearest: 基盤。これがないと何も始まらない
- AimWeakest: 「弱い敵を先に処理する効率 vs 近い敵から片付ける安全」という判断が生まれる
- SpreadOnKill: 「キルした瞬間に報酬（弾幕拡散）」は中毒性が高い。「このチップ拾ったら世界が変わった」体験

## 実装計画

### Phase 1: 最小チップシステム（JSON + BuildSystem拡張）
1. `data/behavior_chips.json` 作成
2. `BuildSystem` にチップスロット管理追加
3. `tower_attack.gd` の `_get_aim_direction()` をチップ駆動に書き換え
4. アップグレードUIにチップ選択肢追加

### Phase 2: トリガー系
5. OnKill トリガー実装
6. HPBelow トリガー実装

### 既存コードとの接続点
- `tower_attack.gd:_get_aim_direction()` → ここがAimチップの接続先
- `tower_attack.gd:_fire()` → SpreadOnKillはここの拡張
- `build_system.gd` → チップスロット管理
- `build_upgrade_ui.gd` → チップ選択UI

## アーキテクチャ判断
チップデータはJSONで定義（データ駆動）。
チップの「効果」は `tower_attack.gd` 内のmatch文で分岐（5種以下なら十分）。
将来的にGDScriptを動的生成する必要はない（現行の弾スクリプト動的生成と同じ複雑度を増やさない）。

## テスト結果 (2026-02-15)
- **Commit**: 8b6339c
- **Kite AI**: 動作確認OK。敵から逃げる→画面角に追い込まれる傾向あり
- **Poison Nova + Spark**: 緑+黄色の弾幕が映える。視覚的フィードバック良好
- **HUD表示**: "AI: Kite / Nearest / Auto Cast" が明確
- **改善候補**: 角追い込み防止（中央引力 or 壁回避AI）、Orbit AIのテスト

## 次の改善（優先度順）
1. Kite AIの角逃げ防止（中央方向への微力バイアス）
2. Orbit AI動作確認
3. On Kill チップの体感テスト（「キルで弾幕」の快感確認）
4. ラン中チップドロップの出現頻度チューニング
