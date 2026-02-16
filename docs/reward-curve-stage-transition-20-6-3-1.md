# Reward Curve & Stage Transition Design (20→6→3→1)
Date: 2026-02-16
Task: explore-spell-cascade-reward-curve-stage-transition-20-6-3-1

## Problem Statement

Quality gate data (6 runs) reveals two systemic issues:
- **Level-ups are TOO FREQUENT**: avg 4.5-9.7s interval → fatigue_rating: TOO_FREQUENT
- **Difficulty is TOO EASY**: 0-4 damage taken per run, HP never drops below 98%
- Enemy count peaks at t=20s (8 enemies), then **collapses** to 2-3 by t=50s
- Power fantasy arc is broken: no struggle phase, no tension, no crisis

The game has good feel metrics (action density 3.0/s, reward freq 79/min) but lacks stakes.

## Current Balance (v0.2.5)

```
XP thresholds:  [5, 12, 22, 36, 55, 80, 115, 160, 220, 300, 400, 520, 660]
Spawn interval: max(1.5 - run_time * 0.002, 0.4)  → caps at ~9 min
Enemy HP:       25.0 * (1.0 + distance/50 + time/120)
Enemy speed:    65.0 + distance*0.1 + time*0.08
Enemy damage:   6.0 + distance*0.02
Enemy types:    60% normal, 25% swarmer, 15% tank (after 50m)
XP drops:       normal=1, swarmer=1, tank=3, boss=10
```

## 20 Ideas

1. **XP threshold +50%**: Stretch level requirements to slow level-up rate
2. **Stage-based enemy waves**: Replace continuous spawning with 3 distinct stages
3. **Enemy damage 2x**: Double base enemy damage from 6→12
4. **Spawn rate floor raise**: Keep minimum 4 enemies alive at all times
5. **Power ratio tracking**: Monitor DPS/incoming and auto-adjust spawn rate
6. **Level-up cooldown**: Minimum 8s between level-ups (queue excess XP)
7. **Late-game swarm event**: At t=40s, spawn 15 enemies simultaneously
8. **Boss HP linked to player level**: Boss scales with upgrades chosen
9. **Distance-gated enemy tiers**: New enemy type every 30m
10. **XP gem merge**: Cap visible orbs at 20, merge excess into high-value gems
11. **Shrine as pacing gate**: Shrine pauses enemy spawning for decision time
12. **Danger meter**: Visible threat indicator that drives spawn escalation
13. **Damage floor**: Enemies guaranteed to deal minimum 1 damage on contact
14. **Speed scaling acceleration**: Enemy speed grows faster after t=30s
15. **Post-boss swarm**: After boss dies, spawn density doubles for 15s
16. **Combo-scaled rewards**: Higher combo = larger XP orbs (reward skilled play)
17. **Upgrade quality gates**: Better upgrades only available after taking X damage
18. **Environmental hazards**: Random obstacles that damage tower if not dodged
19. **Wave clear bonus**: Kill all enemies → brief gold shower + breathing room
20. **Progressive enemy armor**: Later enemies have damage reduction

## Shortlist (6)

### 1. XP Threshold Rebalance (+35%)
- **Value**: Directly fixes fatigue_rating: TOO_FREQUENT
- **Target**: avg interval 5.2s → 8-10s
- **Success metric**: fatigue_rating != TOO_FREQUENT in 5/5 runs
- **Minimum experiment**: Change level_thresholds array, run 3 quality gates
- **Risk**: Low — pure numbers tuning

### 2. Enemy Damage Increase (2x base)
- **Value**: Fixes difficulty_rating: TOO_EASY and zero-damage runs
- **Target**: Player takes 15-20 damage per run, lowest_hp_pct < 90%
- **Success metric**: 0/5 runs with damage_taken=0
- **Minimum experiment**: Change dmg_val formula, run 3 quality gates
- **Risk**: Low — may need HP rebalance if too punishing

### 3. Spawn Floor (minimum 4 enemies alive)
- **Value**: Fixes late-game enemy count collapse (peak=8 → trough=2)
- **Target**: Enemy count never drops below 4 after t=15s
- **Success metric**: All enemy_count_samples ≥ 4 after t=15s
- **Minimum experiment**: Add floor check in spawn logic, run 3 quality gates
- **Risk**: Low — additive, doesn't change early game

### 4. 3-Stage Difficulty Ramp
- **Value**: Creates distinct emotional beats (vulnerability → mastery → crisis)
- **Target**: Stage 1 (0-20s easy), Stage 2 (20-40s power fantasy), Stage 3 (40-60s crisis)
- **Success metric**: HP drops below 90% in stage 3 in 3/5 runs
- **Minimum experiment**: Implement stage-based spawn multiplier, run 3 gates
- **Risk**: Medium — requires careful tuning, may interact with existing balance

### 5. Level-Up Cooldown (minimum 6s between level-ups)
- **Value**: Prevents level-up clustering (2.7s/1.7s/2.0s gaps seen in data)
- **Target**: No consecutive level-ups within 6s of each other
- **Success metric**: Min interval between levelups ≥ 6s in all runs
- **Minimum experiment**: Queue excess XP, delay level-up processing
- **Risk**: Medium — changes feel of XP collection; queued levels may feel laggy

### 6. Post-Boss Survival Wave
- **Value**: Creates Act 4 "crisis" that's currently missing
- **Target**: After boss dies, 15s of 2x spawn rate as victory lap / final challenge
- **Success metric**: Player takes damage during post-boss phase in 3/5 runs
- **Minimum experiment**: Add post-boss spawn modifier, run 3 gates
- **Risk**: Low — isolated to endgame, doesn't affect early/mid balance

## Finalists (3)

### A. XP Threshold Rebalance (+35%)
**Why**: Directly fixes the #1 quality gate issue (pacing_warn / fatigue). Pure data tuning, zero implementation risk, immediately measurable. Every other change benefits from this being fixed first.

### B. Enemy Damage Increase (2x base) + Spawn Floor
**Why**: These two combined fix the #2 issue (TOO_EASY / zero damage). The spawn floor prevents the late-game collapse, and damage increase ensures enemies that reach the tower actually threaten it. Together they create the missing tension.

### C. 3-Stage Difficulty Ramp
**Why**: Creates the emotional arc that makes a run satisfying. Without stages, the game is a flat line. With stages, it becomes: "survive → thrive → fight for your life." Most impactful for player retention but highest implementation effort.

## THE ONE: XP Threshold Rebalance (+35%)

### Rationale
- **Highest certainty**: Pure numbers change, immediately validates via quality gate
- **Prerequisite for all else**: Can't test difficulty changes when the game constantly interrupts with level-ups
- **Measurable**: fatigue_rating, avg_levelup_interval, pacing_warn frequency
- **Reversible**: Array change only, git revert in 5 seconds
- **Enables next steps**: Once pacing is fixed, difficulty changes become testable

### Proposed Changes

Current thresholds:
```
[5, 12, 22, 36, 55, 80, 115, 160, 220, 300, 400, 520, 660]
```

Proposed (+35%):
```
[7, 16, 30, 49, 74, 108, 155, 216, 297, 405, 540, 702, 891]
```

Expected effect:
- Level 2 at ~25-30s (was ~15-20s) — still fast enough to hook
- Mid-game intervals ~10-12s (was ~5-7s) — breathing room between upgrades
- Upgrade menu interruption reduced from ~30s/run to ~20s/run
- fatigue_rating should shift from TOO_FREQUENT → OK

### Validation Plan
1. Apply threshold change
2. Run quality gate 3 times
3. Check: avg_levelup_interval > 8s in all runs
4. Check: fatigue_rating != TOO_FREQUENT in all runs
5. Check: feel scorecard not regressed (action density, reward freq within 25% of baseline)
6. If pass → commit and update baseline
7. Then proceed to "Enemy Damage + Spawn Floor" as next THE ONE

### Dependency Note
This is THE ONE for **this cycle**. The recommended follow-up order:
1. XP Threshold Rebalance ← THIS
2. Enemy Damage Increase + Spawn Floor (fixes difficulty)
3. 3-Stage Difficulty Ramp (adds emotional arc)

Each builds on the previous. Don't skip ahead.

## Reference Data

### VS-Like Level-Up Interval Benchmarks
| Phase | Ideal Interval | Spell Cascade Current | Spell Cascade Target |
|-------|---------------|----------------------|---------------------|
| Early (lvl 1-3) | 15-30s | 7-15s | 15-25s |
| Mid (lvl 4-7) | 30-60s | 2-7s (clustered!) | 20-40s |
| Late (lvl 8+) | 60-90s | 7-13s | 40-60s |

### Power Fantasy Arc (target for Spell Cascade)
```
  Power
  Ratio
  3.0 |                    *****
      |                   *     **
  2.0 |                  *        *
      |                **          *
  1.0 |----***--------*-----------***----
      |   *   **    **                **
  0.5 |  *      ****                    *
      | *                                *
  0.0 +--+----+----+----+----+----+----+--
      0  5   10   15   20   25   30   35  40  50  60s
```

### Files
- Current thresholds: `scripts/tower.gd:30`
- Spawn logic: `scripts/game_main.gd:158, 1000-1019`
- Enemy scaling: `scripts/game_main.gd:777-779, 1002-1005`
- Quality gate data: `quality-gate/gate-log.jsonl`
- Feel baseline: `quality-gate/baselines/latest.json`
