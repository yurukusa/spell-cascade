# v0.4 Stage Ramp Spec (20→6→3→1)
Date: 2026-02-16
Task: explore-spell-cascade-v04-stage-ramp-spec-20-6-3-1

## Problem Statement

v0.3.1 fixed pacing (8-18s intervals) and added meaningful damage (0-8 per run), but the run still lacks **emotional arc**. The game is a flat experience — same enemy types, same spawn pattern, no distinct phases. Successful VS-likes use a 4-act structure: vulnerability → growth → mastery → crisis.

v0.3.1 regression data:
- Run 1: CHALLENGING, 4 damage, 11.7s interval
- Run 2: CHALLENGING, 8 damage, 8.8s interval (HP dropped to 91.7%)
- Run 3: TOO_EASY, 0 damage, 18.3s interval (RNG variance)

The variance between runs is high because there's no designed difficulty curve.

## 20 Ideas for Stage Ramp

1. **3-Act time gates**: Stage 1 (0-20s), Stage 2 (20-40s), Stage 3 (40-60s) with distinct profiles
2. **Visual stage transitions**: Background color shift on stage change
3. **Audio cue on stage change**: Short fanfare or warning sound
4. **Enemy type introduction per stage**: Normal only → +Swarmer → +Tank
5. **Stage-specific spawn multipliers**: 0.8x → 1.0x → 1.5x spawn rate
6. **HP scaling per stage**: 1.0x → 1.3x → 1.8x enemy HP multiplier
7. **Speed scaling per stage**: 1.0x → 1.1x → 1.3x enemy speed multiplier
8. **"Breathing room" between stages**: 2-3 second spawn pause on transition
9. **Stage title overlay**: "Wave 2: Swarmer Assault" text flash
10. **Kill count gates**: Stage advances after N kills (not time)
11. **Boss phase as Stage 4**: Boss fight with unique mechanics
12. **Progressive enemy aggression**: Stage 3 enemies target tower more directly
13. **Stage-locked upgrades**: Certain upgrades only available in later stages
14. **Environmental change per stage**: Rain/fog/darkness in later stages
15. **Stage 3 "desperate push"**: Reduced spawn interval to 0.2s for final 15s
16. **Milestone reward on stage clear**: Guaranteed upgrade event on transition
17. **Enemy density zones**: Stage 2 spawns from both sides, Stage 3 from all sides
18. **Resurrection mechanic in Stage 3**: Dead enemies respawn once
19. **Combo bonus per stage**: Higher combo ceiling in later stages
20. **Stage-specific music**: BGM variation per stage (tempo/key change)

## Shortlist (6)

### 1. 3-Act Time Gates with Spawn Multipliers
- **Value**: Creates distinct phases with clear difficulty progression
- **Target**: Stage 1 (0-20s, 0.8x spawn), Stage 2 (20-40s, 1.2x), Stage 3 (40-60s, 1.6x)
- **Success metric**: Each stage has measurably different enemy_count_samples
- **Effort**: Low — multiply `current_interval` by stage factor
- **Risk**: Low — pure numbers, already have quality gate to validate

### 2. Enemy Type Introduction per Stage
- **Value**: Visual variety + learning curve (new threat each phase)
- **Target**: Stage 1=normal only, Stage 2=+swarmer (25%), Stage 3=+tank (15%)
- **Success metric**: Players encounter new enemies gradually instead of all at once
- **Effort**: Low — gate the existing `type_roll` logic by `run_time`
- **Risk**: Low — types already exist, just timing changes

### 3. Visual + Audio Stage Transition
- **Value**: Player knows "something changed" immediately — emotional punctuation
- **Target**: Background tint shift + warning text + stage-change SE
- **Success metric**: Subjective (screenshot comparison showing visual change)
- **Effort**: Medium — needs tween for background, label for text, SE generation
- **Risk**: Low — cosmetic, doesn't affect gameplay balance

### 4. Breathing Room (2s spawn pause on transition)
- **Value**: Brotato-style "moment to prepare" before difficulty ramp
- **Target**: 2-second spawn pause at each transition, allows player to collect orbs/reposition
- **Success metric**: dead_time increases slightly at transition points (visible in feel data)
- **Effort**: Low — set `spawn_timer = -2.0` on transition
- **Risk**: Low — brief, won't significantly affect overall metrics

### 5. HP Scaling per Stage
- **Value**: Enemies in Stage 3 survive long enough to create real threat
- **Target**: Stage 1=1.0x HP, Stage 2=1.3x, Stage 3=1.8x (on top of progress_scale)
- **Success metric**: difficulty_floor_warn eliminated (damage > 0 in 4/5 runs)
- **Effort**: Low — multiply `hp_val` by stage factor
- **Risk**: Low — tunable, already have quality gate data from v0.3.1

### 6. Stage 3 Desperate Push (0.2s interval for final 15s)
- **Value**: Creates the "crisis" feeling in Act 4 — overwhelming enemy count
- **Target**: Last 15s of run has 2-4x normal spawn rate
- **Success metric**: enemy_count_samples in final 3 samples (t=45-60) are 2x higher than t=30-40
- **Effort**: Low — conditional spawn interval reduction
- **Risk**: Medium — may overwhelm autotest, need to tune carefully

## Finalists (3)

### A. 3-Act Time Gates + Spawn/HP Multipliers (combines ideas 1+5)
**Why**: Creates the fundamental difficulty curve. Everything else is cosmetic or secondary. Pure numbers, low risk, immediately testable. This is the structural backbone.

**Specification**:
```
Stage 1 (Vulnerability): 0-20s
  - spawn_mult: 0.8x (slower spawns, learn the game)
  - hp_mult: 1.0x
  - Enemy types: normal only

Stage 2 (Growth): 20-40s
  - spawn_mult: 1.2x (pressure ramps up)
  - hp_mult: 1.3x
  - Enemy types: normal + swarmer
  - Transition: 2s spawn pause

Stage 3 (Crisis): 40-60s
  - spawn_mult: 1.6x (overwhelming)
  - hp_mult: 1.8x
  - Enemy types: normal + swarmer + tank
  - Transition: 2s spawn pause
  - Final 15s: spawn_mult 2.5x
```

### B. Enemy Type Introduction per Stage (idea 2)
**Why**: Type-gating adds meaningful variety without new assets. Currently all types spawn from the start (after 50m for tanks), which front-loads complexity. Gating creates a "what's this?!" moment at each transition.

### C. Visual + Audio Stage Transition (idea 3)
**Why**: Without signaling, the player doesn't notice the difficulty change. A quick tint shift + text flash + SE makes each stage feel intentional, not random.

## THE ONE: 3-Act Time Gates + Spawn/HP Multipliers

### Rationale
- **Foundation first**: The stage ramp is a structural change. Visual/audio polish is cosmetic. Build the skeleton before adding skin.
- **Data-driven**: Every parameter is testable via quality gate. No subjective judgments needed.
- **Builds on v0.3.1**: v0.3.1 proved that HP+40% and speed+15% create damage. Stage multipliers on top of these create a clear curve.
- **Reversible**: Stage multipliers are simple multipliers on existing formulas. Easy to adjust or remove.

### Implementation Plan

1. Add `current_stage` variable to `game_main.gd` (1=vulnerability, 2=growth, 3=crisis)
2. Add stage transition logic in `_process()`:
   ```
   if run_time >= 40.0 and current_stage < 3:
       current_stage = 3
       spawn_timer = -2.0  # breathing room
   elif run_time >= 20.0 and current_stage < 2:
       current_stage = 2
       spawn_timer = -2.0
   ```
3. Apply `spawn_mult` in spawn interval calculation:
   ```
   var stage_spawn_mult := [0.8, 1.2, 1.6][current_stage - 1]
   var current_interval := maxf(spawn_interval - run_time * 0.002, 0.4) / stage_spawn_mult
   ```
4. Apply `hp_mult` in enemy init:
   ```
   var stage_hp_mult := [1.0, 1.3, 1.8][current_stage - 1]
   var hp_val := 35.0 * progress_scale * stage_hp_mult
   ```
5. Gate enemy types by stage:
   ```
   if current_stage >= 2 and type_roll < 0.25:
       etype = "swarmer"
   if current_stage >= 3 and type_roll >= 0.25 and type_roll < 0.40:
       etype = "tank"
   ```
6. Final 15s desperate push:
   ```
   if run_time >= 45.0:
       stage_spawn_mult *= 1.6  # 1.6 * 1.6 = 2.56x total
   ```

### Validation Plan
1. Implement changes
2. Run quality gate 3 times
3. Check: Stage 1 enemy_count_samples < Stage 3 samples
4. Check: damage_taken > 0 in at least 2/3 runs
5. Check: pacing still in PASS range (8-35s)
6. Check: feel scorecard not severely regressed
7. If PASS → commit + baseline update

### Expected Emotional Arc After Implementation
```
Tension
  HIGH |                              ****
       |                         ****
  MED  |                    ****
       |               ****
  LOW  | ***      *****
       |    ****
  NONE +--+--+--+--+--+--+--+--+--+--+--+--
       0  5  10 15 20 25 30 35 40 45 50 55 60s
       |-- Stage 1 --|-- Stage 2 --|-- Stage 3 --|
       vulnerability    growth         crisis
```

### Future Add-ons (v0.4.1+)
- Visual transition: background tint (Color.lerp per stage)
- Audio transition: tempo-shifted BGM per stage
- Stage title text flash overlay
- Combo bonus ceiling increase per stage

## Files
- Spawn logic: `scripts/game_main.gd:158-168`
- Enemy init: `scripts/game_main.gd:1000-1019`
- Boss spawn: `scripts/game_main.gd:775-790`
- Reward curve design: `docs/reward-curve-stage-transition-20-6-3-1.md`
