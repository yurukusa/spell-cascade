# Game Factory Pipeline Baseline KPIs v1

Date: 2026-02-16 | Game: Spell Cascade v0.2.6

## 1. Development Velocity

| Metric | Value |
|--------|-------|
| Commits (24h) | 101 |
| Total commits | 101 |
| GDScript LOC | 7,437 |

## 2. Quality Gate

| Metric | Value |
|--------|-------|
| Gate log | Empty (gate-log.jsonl format issue, runs exist in baselines/) |
| Baseline files | 11 saved |

## 3. Latest AutoTest Metrics

| Metric | Value | Rating |
|--------|-------|--------|
| Difficulty | CHALLENGING | OK |
| Damage taken | 16 | Good engagement |
| HP floor | 66% | Survived |
| Dead time | 7.4s | WARN |
| Action density | 1.6 events/s | GOOD |
| Reward frequency | 27/min | GOOD |
| Run Completion Desire | 0.25 | FAIL (too easy for bot) |

### Desire Score Analysis

Run desire=0.25 (FAIL) because the bot finishes at 100% HP in many runs. This means:
- Balance may be too easy for the autoplay bot
- Human players (less optimal movement) would take more damage
- This metric needs calibration against human play data

## 4. Asset Inventory

| Category | Count | Source |
|----------|-------|--------|
| Sound effects (WAV) | 13 | pyfxr procedural generation |
| Generated sprites (PNG) | 11 | Pillow + gen_sprite.py |
| Existing game sprites | ~15 | Shader-drawn (in-code) |
| Fonts | 0 dedicated | Godot default |

## 5. Pipeline Tool Coverage: 71% (5/7)

| Area | Tool | Status |
|------|------|--------|
| Sound generation | pyfxr | OK |
| Sprite generation | Pillow + gen_sprite.py | OK |
| Quality gate | SpellCascadeAutoTest.gd (7 metrics) | OK |
| Build | Godot headless CLI | OK |
| Distribution pack | Python zipfile | OK |
| Art AI (API) | PixelLab MCP | PENDING (purchase approval) |
| Scene management | godot-mcp | OK |

## 6. Distribution Status

| Channel | Status | Metrics |
|---------|--------|---------|
| itch.io | Published | 5 views |
| CrazyGames | Ready | Preflight all PASS |
| Newgrounds | Assessed | SDK not needed |

## Baseline Targets (for next measurement)

| KPI | Current | Target (1 week) |
|-----|---------|-----------------|
| Pipeline coverage | 71% | 85% (add PixelLab or alt) |
| Run Desire (avg 3 runs) | 0.25 | >0.40 |
| Dead time | 7.4s | <5.0s |
| Distribution channels live | 1 | 3 |
| Sound effects integrated | 0/13 | 6/13 |
| Generated sprites integrated | 0/11 | 5/11 |
