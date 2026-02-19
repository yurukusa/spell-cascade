# Changelog

## v0.9.3 (2026-02-20)

### Balance: XP Curve Rebalance — pacing_warn Fix

**Problem**: quality-gate reported avg_levelup_interval = 5.2s (threshold: min 8.0s).
Level-ups were happening too frequently, reducing upgrade weight/anticipation.

**Fix**: All 20 XP thresholds multiplied by ×1.5:
- Before: `[10, 22, 40, 65, 100 ...]`
- After:  `[15, 33, 60, 98, 150 ...]`

Expected result: avg_levelup_interval ~7.8–8.5s (passes min_avg_interval: 8.0)

This also reduces the "upgrade feast in first 3 minutes" problem noted in playtest_log.

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
