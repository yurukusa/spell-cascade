# Changelog

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
