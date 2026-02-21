# Changelog

## v0.11.2 (2026-02-21)

### Feature: Daily Challenge → itch.io コメント欄直接リンク (改善212)

Daily Challenge リザルト画面に「💬 Post to itch.io comments」ボタン追加。
Copy Score でスコアをクリップボードにコピーした後、itch.io のコメント欄に直接ジャンプできる。

**設計意図**: Daily Challenge は全プレイヤーが同じシードで遊ぶため、コメント欄がリーダーボード代わりになる。
スコアコピー → コメント欄へのフローを 2 クリックに短縮してソーシャル摩擦をゼロにする。

- Web 環境のみ表示 (`OS.has_feature("web")` 判定)
- Daily Challenge 時のみ表示 (`is_daily_challenge` フラグ)
- クリックで `window.open('yurukusa.itch.io/spell-cascade#comments', '_blank')`

## v0.11.1 (2026-02-21)

### Feature: Copy Score ボタン — クリップボードシェア (改善210)

リザルト画面に「📋 Copy Score」ボタン追加。クリックするとスコアをクリップボードにコピー。
Daily Challengeと組み合わせると「今日のスコアをitch.ioコメントに貼る」フローが1クリックになる。

**シェアテキスト形式**:
- Daily: `[Spell Cascade Daily] 🗡️ Phantom Executioner ★★★ | Endless +8:30 | 412 kills`
- Normal: `[Spell Cascade Run] 💀 Chain Annihilator ★★ | 7:42 | 187 kills`

Web: `JavaScriptBridge.eval("navigator.clipboard.writeText(...)")` / Native: `DisplayServer.clipboard_set()`
コピー後「✓ Copied!」→1.5秒後に元テキストに戻る。

## v0.11.0 (2026-02-21)

### Feature: Daily Challenge Mode — コミュニティチャレンジ

**背景**: ビルド名(v0.10.0)でSNSシェアフックができた。次の問題: 「俺のPhantom Executioner」はユニークだが比較できない。

**解決**: タイトル画面に「Daily Challenge MM/DD」ボタン（オレンジ）を追加。
押すと日付ベースのシードで全プレイヤーが同じ敵スポーン・タイプ・アップグレード選択を経験。

**実装詳細**:
- `title.gd`: `_on_daily()` 関数 — `date.year×10000 + date.month×100 + date.day × 31337` でシード生成。`Engine.set_meta("daily_challenge_seed", seed)` でゲームシーンに渡す
- `game_main.gd`: `_ready()` で `Engine.has_meta("daily_challenge_seed")` チェック。見つかれば `seed()` 設定 + `is_daily_challenge = true` + メタ削除（次回持ち越しなし）
- `game_main.gd`: リザルト画面に「★ DAILY CHALLENGE MM/DD ★」バッジ（改善209）

**技術ポイント**: `seed()` でGodotグローバル乱数を設定すると、wave_manager/enemy/tower_attackの全 `randi()`/`randf()` に自動反映。Autoload追加不要。5行の変更で完結。

## v0.10.1 (2026-02-21)

### Feature: SOLO WARRIOR 実績バナー

サポートを一切装備せずにEndless Modeに到達すると「★ SOLO WARRIOR ★」バナーを表示。
ハードモード自然発生プレイへの報酬。コスト: 15行。

## v0.10.0 (2026-02-21)

### Feature: Build Name Auto-generation — ランのアイデンティティ化

**背景**: ランが終わっても「どんなビルドだったか」が残らない。SNSで共有するフックがない。

**解決**: リザルト画面にビルド名を自動表示。シナジー組み合わせからユニークな名前を生成。

- `game_main.gd`: `_generate_build_name()` 関数追加
  - シナジー1種 → 専用名（例: `phantom_punisher` → "Phantom Executioner"）
  - シナジー2種 → コンボ名またはメインシナジー名（例: "Undying Phantom"）
  - シナジー3種以上 → "Perfect Cascade"
  - シナジーなし → サポートから命名（例: "Chain & Pierce Caster"）
  - 何もなし → "Solo Wanderer"
- リザルト画面に `[ ビルド名 ]` をシアン色で表示（区切り線とスター評価の間）

### Feature: ランサマリー強化 — 達成の可視化 + シェアフック (案3+案4)

- Endless達成時のTimeスタッツ表示を `Endless  +8:30` 形式に変更（継続時間を強調）
- Endless達成時のリザルト画面に「Post your Endless score in itch.io comments!」を表示
  → コメント欄が自然なリーダーボードとして機能する設計

## v0.9.9 (2026-02-21)

### Feature: Endless Mode — Wave 20後も続行、スコアアタック化

**問題**: Wave 20クリアで即「YOU WIN」となり、ゲームが10分で完全終了していた。
ゲームジャム投票者が10分プレイして終わるため、より長く遊べる動線がなかった。

**解決**: Wave 20クリア後に自動でEndless Modeへ移行。

- `wave_manager.gd`: `endless_mode`フラグ追加。Wave 21以降も波を継続生成。
  敵数上限60体（爆発防止）、phantomウェイトを上限60でキャップ。
- `main.gd`: `all_waves_cleared`シグナルをEndless移行に転換。
  "★ ENDLESS MODE ★" 1.5秒アナウンス後にWave +1, +2... と継続。
  タイマー表示をカウントダウン→カウントアップ(+mm:ss)に切替。
  Endlessスコア（waveクリア数）をwave_labelに表示。
  10分タイマー勝利条件はEndless中は無効化。

**Endlessの終了条件**: プレイヤー死亡のみ（Rキーでリスタート）

---

## v0.9.8 (2026-02-21)

### Feature: Phantom Punisher シナジー

pierce + trigger サポート組み合わせ時、phantomの脆弱フェーズ(1.5s)に+60%ダメージ。
タイミング読みを「スキル」として報酬化する。

- `synergies.json`: `phantom_punisher`エントリ追加
- `enemy.gd`: `get_is_phantom_vulnerable()`メソッド + 赤フラッシュVFX
- `tower_attack.gd`: 弾ヒット時のダメージ乗算ロジック
- `game_main.gd`: シナジー有効時のstats注入

---

## v0.9.5 (2026-02-20)

### Feature: アップグレードプール拡張 6→13 — ビルド多様性向上

**問題**: 6種類のアップグレードでは3回のレベルアップで全種類を見てしまい、
以降は同じ選択肢が繰り返され選択が形式的になっていた。

**追加した7アップグレード**:
- `damage_big` — +50% Damage（攻撃強化の上位選択肢）
- `fire_rate_big` — +35% Fire Rate（攻撃速度の上位選択肢）
- `attract_big` — +200 Attract Range（XPオーブ吸引範囲大拡張）
- `max_hp_big` — +150 Max HP + Heal 75（HP強化の上位選択肢）
- `regen` — HP Regen +3/s（毎秒3HP自動回復。tower.gd に regen_rate 変数を追加）
- `armor` — Armor: -20% Damage Taken（被ダメ軽減。tower.gd に armor_mult を追加）
- `heal_now` — Emergency Repair: Heal 100 HP（即時回復。低HP時の選択肢）

**技術変更** (tower.gd):
- `regen_rate` 変数追加。`_process`で蓄積→`heal()`呼び出し（1秒単位でまとめてVFX節約）
- `armor_mult` 変数追加。`take_damage`で `amount * armor_mult` を適用

---

## v0.9.4 (2026-02-20)

### Fix: クラッシュ防止ガード多数 — Web環境安定化

ツリー外ノードへの操作で発生する `get_tree()` 系エラーをすべてガード:

- **auto_attack.gd**: `add_child` 前にツリー存在確認（ツリー外なら bullet を解放）
- **enemy.gd**: `_spawn_entry_flash()` を `init()` から `_ready()` へ移動（ツリー追加後に実行する必要があるため）
- **player.gd**: `_hit_feedback` コルーチン内でツリー脱退を検知して `time_scale` を復元
- **sfx.gd**: `play_boss_warning` コルーチンの await 前後でツリー確認
- **title.gd**: `_transitioning` フラグ追加でダブルクリック/連打による二重シーン遷移を防止
- **wave_manager.gd**: `_on_enemy_died` コルーチン内の await 前後でツリー確認

これらは特にWeb(HTML5)ビルドでゲーム終了時/シーン遷移時に発生するクラッシュを防ぐ。

---

## v0.9.3 (2026-02-20)

### Audio: BGM License Documentation + Intense Track Added

**battle.mp3** (already present, license now documented):
- DST "Tower Defense Theme" — CC0 1.0 (Public Domain)
- MD5 verified match to https://opengameart.org/content/tower-defense-theme
- Used: gameplay BGM, Wave 1–15, normal state

**battle_intense.mp3** (newly added):
- DST "Return of Tower Defense Theme" — CC0 1.0 (Public Domain)
- Source: https://opengameart.org/content/return-of-tower-defense-theme
- Used: Wave 16+, HP<25%, Stage 3 (sfx.gd already handled switching, was falling back to procedural)

THIRDPARTY.md updated with both entries including source URLs and MD5 for battle.mp3.

### Balance: XP Curve Rebalance — pacing_warn Fix

**Problem**: quality-gate reported avg_levelup_interval = 5.2s (threshold: min 8.0s).
Level-ups were happening too frequently, reducing upgrade weight/anticipation.

**Fix**: All 20 XP thresholds multiplied by ×1.5:
- Before: `[10, 22, 40, 65, 100 ...]`
- After:  `[15, 33, 60, 98, 150 ...]`

Expected result: avg_levelup_interval ~7.8–8.5s (passes min_avg_interval: 8.0)

This also reduces the "upgrade feast in first 3 minutes" problem noted in playtest_log.

### Balance: Dead Zone Fix (120-225s) — Spawn Acceleration Reduced

**Problem**: playtest_log identified 120-225s as a dead zone where enemy scaling outpaced upgrade arrival.
With XP thresholds ×1.5 (above), the dead zone worsened further — players spent longer between upgrades
while enemy spawn rate continued to accelerate at 0.002/s.

**Fix**: Spawn acceleration coefficient reduced from 0.002 → 0.0012 (−40%):
- Before at 120s: maxf(1.0 − 0.24, 0.4) / stage_spawn = 0.475s per spawn
- After  at 120s: maxf(1.0 − 0.144, 0.4) / stage_spawn = 0.535s per spawn (+13% breathing room)
- Before at 225s: maxf(1.0 − 0.45, 0.4) / stage_spawn = 0.344s per spawn
- After  at 225s: maxf(1.0 − 0.27, 0.4) / stage_spawn = 0.456s per spawn (+33% breathing room)

Expected result: Difficulty Curve dimension improves 3/5 → 4/5 (GAME_QUALITY_FRAMEWORK target).

---

## v0.9.2 (2026-02-20)

### CRITICAL Visual Overhaul — Game Jam Submission Quality

**Goal**: 17/50 → 34/50 visual quality score (target 25/50 ✅)

**Player**:
- Sprite: tile_0100 (blue/gray armored knight) — clear humanoid identity

**Enemies** (v0.9.1):
- 7 distinct Kenney tiny-dungeon sprites replace uniform red polygon
- normal=demon, swarmer=slime, tank=armored beast, shooter=skeleton,
  splitter=brown creature, healer=purple mage, boss=fire creature
- Type-specific animations: boss pulse, swarmer fast-pulse, tank aura

**Background** (v0.9.0 + v0.9.2):
- ProceduralBackground: Kenney stone floor tiles (16×16, 8× scaled)
- Rune circles with breathing pulse, column stumps, debris
- Barrel (tile_0042) 10% + chest (tile_0030) 5% per row — dungeon density

**Projectiles** (v0.9.1):
- 6 elemental types: fireball, ice shard, spark, poison, holy, default
- 3× scale baseline for combat readability
- Trail effects, muzzle flash per shot

**VFX**:
- Hit flash (Color.WHITE, 50ms) on all enemy types
- Death VFX: 7 type-specific particle bursts (4–16 fragments)
- XP orb: blue-purple glow + pulse + trail + collection sparkle

**UI** (v0.9.1):
- Silkscreen pixel font (project-wide theme)
- HP bar, XP bar, combo bar, wave/timer/distance labels restyled
- Build label permanently hidden (debug text removal)

**Debug cleanup**:
- AutoPlayer debug autoload removed
- ScreenshotCapture moved to debug-only scripts

**HTML5 Build**:
- exports/web/ rebuilt with all v0.9.x changes

## v0.8.3 (2026-02-19)

### Quality Loops 1-4 Complete — 143 Improvements

**Loop 1 (改善1-20): Sakurai-principle — 宮崎英高式基礎固め**
- タワーHP表示、コンボ表示、ダメージ数字、死亡エフェクト等

**Loop 2 (改善21-50): Steam-grade Polish**
- ヒットストップ、画面シェイク、パーティクル強化、BGM追加

**Loop 3 (改善77-100): VFXシステム強化**
- デスリング、コンボブレーク、ステージ遷移エフェクト

**Loop 4 (改善101-143): ジュース感最終強化**
- 高コンボブレーク時シェイク、Shrine UIフラッシュ、ボスPhase移行スパーク
- 高XP敵の大デスリング、レベルアップXPバウンス、ボスチャージ軌跡
- スプリッター分裂バースト、大ダメージUIフラッシュ、クラッシュ2重衝撃波
- マズルフラッシュ、holyタグ十字スパーク、HP30%点滅
- Ko-fi CTA をリザルト画面に追加

## v0.3.4 (2026-02-17)

### Run Desire Fix (0.48 → 0.79-0.94)
- HP orb heal: 15% → 13%（ダメージが蓄積しやすくなり、緊張感UP）
- 根本原因: 15%回復だと60s間に3,750+HP回復→常にほぼ全快→Run Desire低下
- 13%により最終HP 46-64%（理想値50%付近）で安定

### Quality Gate Results (2-run A/B)
| 指標 | v0.3.3 | v0.3.4 Run A | v0.3.4 Run B |
|------|--------|-------------|-------------|
| Dead Time | 4.4s (GOOD) | 5.3s (WARN) | 9.7s (WARN) |
| Pacing | 10.8s (OK) | 11.3s (OK) | 6.5s (OK) |
| Run Desire | 0.48 (WARN) | 0.94 (EXCELLENT) | 0.79 (GOOD) |
| Final HP | ~85% | 46% | 64% |

### Rejected Approaches
- enemy dmg 14→18: A/B分散大（desire 0.61 vs 0.25）、Pacing悪化
- heal 10%: 過激（desire 0.87 vs 0.28、プレイヤー瀕死）
- heal 12%: やや過激（Run Bでプレイヤー死亡）

## v0.3.3 (2026-02-17)

### Dead Time Fix (11.2s → 4.4s)
- Initial wave: ゲーム開始時に近距離(150-250px)に4体スポーン
- spawn_interval: 1.2s → 1.0s
- Spawn floor: t=5s/min4体 → t=3s/min6体
- XP thresholds: +20%（pacing改善、TOO_FREQUENT→OK）

### Quality Gate Results
| 指標 | v0.3.2 | v0.3.3 |
|------|--------|--------|
| Dead Time | 11.2s (FAIL) | 4.4s (GOOD) |
| Pacing | 5.4s (TOO_FREQUENT) | 10.8s (OK) |
| Run Desire | 0.63 (GOOD) | 0.48 (WARN) |

## v0.3.2 (2026-02-17)

### Hitstop Safety
- Engine.time_scale操作を`_do_hitstop()`に完全一元化
- リエントラントカウンタ（`_hitstop_depth`）で重複呼び出し時の早期復帰を防止
- `_reset_time_scale()`: game over / scene遷移の全5経路に配置
- `_exit_tree()`: シーン破棄時の強制リセット
- 自動テスト: 3ケース14アサーション全PASS

### Balance (Feel Improvement)
- spawn_interval: 1.5s → 1.2s（序盤の敵密度UP）
- Stage 1 spawn mult: 0.8 → 1.0（序盤スロースタート廃止）
- Base enemy damage: 10 → 14（HP500に対して体感できるダメージ）
- Spawn floor: t=15s → t=5s（序盤の空白時間削減）

### Quality Gate Results
| 指標 | v0.2.3 | v0.3.2 |
|------|--------|--------|
| Dead Time | 15.3s | 11.2s |
| Run Desire | 0.25 (FAIL) | 0.63 (GOOD) |
| Action Density | 1.1/s | 3.3/s |
| Kills/60s | 7 | 63 |
| Lowest HP | 100% | 54% |
| Level ups | 1 | 6 |

### Bugfix
- project.godot: autoloadセクション外の重複エントリ削除
