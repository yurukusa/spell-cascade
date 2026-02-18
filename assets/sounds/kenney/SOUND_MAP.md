# Kenney CC0 Audio — Spell Cascade Sound Map

**Source**: kenney.nl (5 packs: Music Jingles, Digital Audio, RPG Audio, Interface Sounds, Impact Sounds)
**License**: CC0 (Public Domain) — see LICENSE-CC0.txt
**Date**: 2026-02-16

## BGM / Jingles (4 files)

| Game Sound | File | Kenney Source | Notes |
|-----------|------|---------------|-------|
| Victory Fanfare | bgm/victory_fanfare.ogg | jingles_NES00 | 10分クリア時 |
| Game Over | bgm/game_over.ogg | jingles_NES03 | 死亡時 |
| Boss Entrance | bgm/boss_entrance.ogg | jingles_NES05 | ボス出現ジングル |
| Level Up Fanfare | bgm/level_up_fanfare.ogg | jingles_NES11 | レベルアップ時 |

**NOTE**: ジングルは短い(2-10秒)。メインBGMループ(30-60秒)は別途必要。
現在のランタイム生成BGM(_gen_bgm(), 8秒Am)はジングルでは代替不可。
→ freesound.org CC0 or pyfxr拡張 or 別のKenneyパックを検討。

## SFX (15 files)

| Game Sound | File | Kenney Source | 用途 |
|-----------|------|---------------|------|
| Shot (Laser) | sfx/shot_laser.ogg | laser3 | 弾発射 |
| Shot (Alt) | sfx/shot_laser_alt.ogg | laser7 | 弾発射バリアント |
| Spark Zap | sfx/spark_zap.ogg | zap1 | Spark属性攻撃 |
| Spark Zap Alt | sfx/spark_zap_alt.ogg | zap2 | Spark属性バリアント |
| Boss Phase | sfx/boss_phase_change.ogg | phaserDown1 | ボス形態変化 |
| Power Up | sfx/power_up.ogg | powerUp3 | パワーアップ取得 |
| XP Collect | sfx/xp_collect.ogg | powerUp7 | XP回収 |
| Explosion | sfx/explosion.ogg | spaceTrash3 | 敵撃破 |
| Low HP | sfx/low_hp_warning.ogg | lowDown | HP低下警告 |
| Damage Taken | sfx/damage_taken.ogg | highDown | 被ダメージ |
| Hit Impact 1 | sfx/hit_impact_1.ogg | impactMetal_light_000 | 弾ヒット |
| Hit Impact 2 | sfx/hit_impact_2.ogg | impactMetal_light_001 | 弾ヒットバリアント |
| Hit Impact 3 | sfx/hit_impact_3.ogg | impactMetal_light_002 | 弾ヒットバリアント |
| Hit Generic 1 | sfx/hit_generic_1.ogg | impactGeneric_light_000 | 汎用ヒット |
| Hit Generic 2 | sfx/hit_generic_2.ogg | impactGeneric_light_001 | 汎用ヒットバリアント |

## UI (7 files)

| Game Sound | File | Kenney Source | 用途 |
|-----------|------|---------------|------|
| UI Select | ui/ui_select.ogg | select_001 | メニュー選択 |
| UI Select Alt | ui/ui_select_alt.ogg | select_003 | メニュー選択バリアント |
| Shrine Select | ui/shrine_select.ogg | confirmation_001 | 祭壇アイテム選択 |
| Shrine Confirm | ui/shrine_confirm.ogg | confirmation_002 | 祭壇確定 |
| UI Cancel | ui/ui_cancel.ogg | close_001 | キャンセル/戻る |
| UI Error | ui/ui_error.ogg | error_004 | エラー音 |
| UI Click | ui/ui_click.ogg | click_003 | ボタンクリック |

## 未カバー（別途必要）

| Sound | 現状 | 推奨対応 |
|-------|------|---------|
| **メインBGM** | ランタイム生成8秒ループ | CC0ループ楽曲を探す (freesound.org) |
| **タイトルBGM** | なし | 上記と同時に探す |
| **環境音** | なし | v0.3 NICE TO HAVE |
