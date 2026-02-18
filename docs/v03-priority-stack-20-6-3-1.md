# v0.3 Priority Stack (20→6→3→1)

**Date**: 2026-02-16
**Task**: explore-b31-priority-stack-v03-20-6-3-1
**Current Version**: v0.3.2 (sound + rebalance + 3-act stage ramp)

## Problem Statement

v0.3.x で Sound (v0.3.0) と Stage Ramp (v0.3.2) を実装済み。
次バッチ (B31) で何に投資するか。ぐらす不在でも迷わない優先順を確定する。

**制約**: 人間レビュー必須の案は減点。再現性と自律実行を最優先。

## Scoring Axes (各1-5, max 20)

- **V (Value)**: プレイヤー体験への影響度
- **E (Effort)**: 工数の少なさ（5=1h以内, 1=1日以上）
- **A (Autonomy)**: 人間介入なしで完遂できるか（5=完全自律, 1=承認必須）
- **R (Risk)**: 失敗リスクの低さ（5=回帰なし, 1=ゲーム壊す可能性）

---

## 20 Candidates

| # | 候補 | V | E | A | R | 合計 | カテゴリ |
|---|------|---|---|---|---|------|----------|
| 1 | Kenney CC0 スプライト差替え | 5 | 3 | 5 | 4 | 17 | Art |
| 2 | XP閾値 +35% リバランス | 4 | 5 | 5 | 4 | 18 | Balance |
| 3 | 敵ダメージ 2倍 | 4 | 5 | 5 | 3 | 17 | Balance |
| 4 | Spawn Floor (最低4体維持) | 3 | 4 | 5 | 4 | 16 | Balance |
| 5 | Kenney用 import_assets.py | 4 | 3 | 5 | 4 | 16 | Art/Tool |
| 6 | Feel Auto-Evaluator (H20実装) | 3 | 3 | 5 | 5 | 16 | Infra |
| 7 | CrazyGames SDK統合 | 4 | 2 | 4 | 3 | 13 | Distribution |
| 8 | 敵タイプ新規追加 (Charger) | 4 | 3 | 4 | 3 | 14 | Content |
| 9 | BGMバリエーション (Stage別) | 3 | 3 | 5 | 5 | 16 | Sound |
| 10 | PixelLab MCP ($24/月) | 5 | 2 | 5 | 3 | 15 | Art |
| 11 | Level-Up演出強化 (パーティクル) | 3 | 4 | 5 | 5 | 17 | Feel |
| 12 | Combo Systemメーター | 3 | 3 | 4 | 3 | 13 | Content |
| 13 | Newgrounds 提出 | 3 | 3 | 3 | 4 | 13 | Distribution |
| 14 | r/WebGames 投稿 | 2 | 5 | 3 | 5 | 15 | Distribution |
| 15 | レベルアップ選択肢 UI改善 | 3 | 3 | 4 | 4 | 14 | UI |
| 16 | Wave Clear演出 (報酬シャワー) | 3 | 4 | 5 | 5 | 17 | Feel |
| 17 | HP/ダメージの視覚フィードバック | 4 | 4 | 5 | 5 | 18 | Feel |
| 18 | ボス戦メカニクス改良 | 4 | 2 | 4 | 2 | 12 | Content |
| 19 | Death Screen + リプレイUI | 3 | 4 | 5 | 5 | 17 | UI |
| 20 | 自動スクリーンショット差分テスト | 2 | 3 | 5 | 5 | 15 | Infra |

---

## Shortlist (6)

### 1. XP閾値 +35% リバランス (18pt)
- Quality Gateデータが根拠: avg_interval 4.5-7.0s → 目標8-10s
- **工数**: level_thresholds配列を1行変更 → QG 3回実行 → 完了
- **リスク**: 純粋な数値調整、回帰なし
- **自律度**: 完全自律（承認不要）

### 2. HP/ダメージの視覚フィードバック (18pt)
- 被弾時に画面フラッシュ + ダメージ数値ポップアップ
- **根拠**: Quality Gateで「damage=0なのにGO」が頻出 → プレイヤーが被弾を認識できていない
- **工数**: 3-4時間（シェーダー + ポップアップシーン）
- **自律度**: 高い（パターン既知）

### 3. Kenney CC0 スプライト差替え (17pt)
- プログラマーアート(2/10) → Kenney素材(6/10)への視覚的ジャンプ
- **根拠**: CrazyGames/Newgrounds提出の前提条件
- **工数**: 半日（ダウンロード + マッピング + テスト）
- **自律度**: 完全自律（CC0、wget取得可）

### 4. 敵ダメージ 2倍 (17pt)
- base 6→12。Quality Gateの zero-damage run を解消
- **工数**: 1行変更 + QG 3回
- **リスク**: ceiling fail (NO-GO) を引き起こす可能性 → 段階的(1.5x→2x)が安全

### 5. Level-Up演出強化 (17pt)
- パーティクル爆発 + 画面フリーズ (50ms) + サウンド
- **根拠**: VS-likeの「レベルアップの快感」が不足
- **工数**: 2-3時間
- **自律度**: 高い

### 6. Wave Clear演出 (17pt)
- Wave終了時のXPシャワー + 短いファンファーレ（既にv0.3.0で実装済み）
- **工数**: 2時間（パーティクル + タイマー）
- **自律度**: 高い

---

## The 3

### F-A: バランス一括調整 (XP +35% + ダメージ 1.5x)
- **合体理由**: 両方とも1行変更。Quality Gate 3回で検証可能
- **工数合計**: 1時間
- **期待効果**: zero-damage run消滅、avg_interval 8-10s安定
- **判定基準**: QG 5回連続でdifficulty_floor_warn なし

### F-B: ゲームフィール強化 (被弾フィードバック + Level-Up演出)
- **合体理由**: どちらも「手触り」カテゴリ。同時に入れることでジュース感が一気に上がる
- **工数合計**: 6-8時間
- **期待効果**: Feel Scorecard の Reward Frequency 改善
- **判定基準**: プレイして「気持ちいい」と感じるか → スクショ比較

### F-C: Kenney CC0 アート差替え
- **単独理由**: 他の候補と合体不可（工数が大きく独立タスク）
- **工数**: 8-12時間
- **期待効果**: 視覚品質 2/10 → 6/10、配信PF提出の前提条件クリア
- **判定基準**: CrazyGames Basic Launch 申請可能な視覚品質

---

## THE ONE: F-A — バランス一括調整

### 選定理由

1. **最小工数・最大効果**: 2行変更 + QG 3回 = 1時間で完了
2. **Quality Gateのデータ駆動**: 「なぜこれをやるか」が定量的に明白
3. **完全自律**: ぐらすの判断不要。数値変更 → QG実行 → GO確認
4. **他の候補のベースになる**: バランスが崩れたままFeelやArtを入れても無意味
5. **再現性100%**: 同じ変更を入れれば同じ結果。主観判断なし

### 捨てる理由

- **F-B (Feel強化)**: 効果は高いがバランス修正が先。zero-damageでLevel-Up演出を追加しても虚しい
- **F-C (Art差替え)**: 工数が大きく、バランス修正なしでは「綺麗だけどつまらない」になる

### 実行計画

```
Step 1: バックアップブランチ作成
Step 2: level_thresholds を +35% に変更
Step 3: enemy_damage を 6.0 → 9.0 (1.5x) に変更
Step 4: Quality Gate --skip-run なしで3回実行
Step 5: 3回中2回以上 GO (difficulty_floor_warn なし) → 成功
Step 6: 失敗時は +25% / 1.3x に下げて再試行
Step 7: ベースライン保存、VERSIONをv0.3.3にバンプ
```

### B31の次 (B32候補)

1. F-B (Feel強化) — バランス安定後に着手
2. F-C (Art差替え) — B32-B33で段階実行
3. CrazyGames SDK統合 — Art差替え後
