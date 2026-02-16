# Feel Auto-Evaluator Heuristics: 20 -> 6 -> 3 -> 1

Date: 2026-02-16
Context: Spell Cascade v0.3.2 (VS-like auto-battler, Godot 4.3, 60s runs)

## Problem Statement

The quality gate catches stability (crashes, fires, level-ups) and balance (damage taken, HP floor, pacing intervals, enemy density) and already has a Feel Scorecard (dead time, action density, reward frequency). But **none of these answer the question: "Is this run fun?"**

Fun in a VS-like is not a single metric. It is an emergent property of an *arc* -- the shape of a run over time. A run where action density is 5.0 events/sec but uniformly flat feels monotonous. A run where it oscillates between 2.0 and 8.0 with a crescendo toward the end feels thrilling. The numbers can be identical in aggregate and completely different in feel.

We need heuristics that capture **temporal shape** -- not just averages, but *curves*, *transitions*, and *contrasts*.

### What We Can Already Measure (AutoTest Telemetry)

| Signal | Source | Granularity |
|--------|--------|-------------|
| `fire_count` per skill | `TowerAttack.fire_count` | Cumulative |
| `kill_count` | `game_main.kill_count` | Cumulative |
| `xp_pickup_count` | `feel_xp_pickup_count` | Cumulative |
| `level_up` timestamps | `qm_levelup_timestamps[]` | Per-event |
| `hp_samples` | `qm_hp_samples[]` | Every 5s `{t, hp, hp_pct}` |
| `enemy_count_samples` | `qm_enemy_count_samples[]` | Every 5s `{t, count}` |
| `damage_taken_count` | `qm_damage_taken_count` | Cumulative |
| `upgrade_menu_total_time` | `qm_upgrade_menu_total_time` | Cumulative |
| `feel_event_timestamps` | `feel_event_timestamps[]` | Per-event (fires, kills, pickups, damage) |
| `screenshots` | PNG at 10s intervals | 7 per 60s run |
| `combo_count` / `best_combo` | `game_main.combo_count` | Live / final |
| `current_stage` | `game_main.current_stage` | 1/2/3 |
| `player_level` | `tower.level` | Cumulative |
| `distance_traveled` | `tower.distance_traveled` | Cumulative |

### What Makes a VS-Like Run "Fun" (Design Reference)

From `docs/vs-like-game-design-research.md`:

1. **Power fantasy arc**: vulnerable start -> exponential growth -> godlike endgame
2. **"One more run" feeling**: the run ended while you still wanted more
3. **Pressure-relief-pressure cycle**: alternating tension (enemies closing in) and release (level-up power spike)
4. **Reward frequency > magnitude**: many small dopamine hits beat few large ones (~23s intervals in VS)
5. **Progressive visual chaos**: screen goes from clean to beautifully chaotic -- chaos IS the reward
6. **Meaningful choices that change playstyle**: upgrades should feel impactful, not incremental

---

## The 20 Heuristics

Scoring: each axis is rated 1-5.
- **Fun (F)**: How well does this capture actual fun? (5 = directly maps to enjoyment)
- **Auto (A)**: Can it be computed purely from autotest telemetry? (5 = trivial formula, 1 = needs new instrumentation)
- **Ease (E)**: How easy to implement in SpellCascadeAutoTest.gd? (5 = <10 lines, 1 = architecture change)

---

### H01: Power Ratio Curve (T=0 vs T=30 vs T=60)

**Definition**: Ratio of kills-per-5s-window at the end of the run vs. the beginning. Measures whether the player *feels* more powerful over time.

**Formula**: `power_ratio = kills_in_last_15s / max(kills_in_first_15s, 1)`

**Target**: 2.0-5.0x (you should be 2-5 times stronger at the end than the start)

| F | A | E | Total |
|---|---|---|-------|
| 5 | 3 | 3 | 11 |

**Why this score**: The power fantasy arc IS the VS-like genre. A flat or declining power ratio means the run lacks the fundamental hook. Score docked on Auto/Ease because it requires tracking kills per time window (not currently done -- events are timestamped but not bucketed).

---

### H02: Tension Oscillation Index

**Definition**: Number of times HP changes direction (rising to falling, or falling to rising) across 5s samples. Measures the presence of pressure-relief-pressure cycles.

**Formula**: Count sign changes in `hp_samples[i].hp - hp_samples[i-1].hp`

**Target**: 3-8 oscillations per 60s run (some pressure, some relief, not flat)

| F | A | E | Total |
|---|---|---|-------|
| 4 | 5 | 5 | 14 |

**Why this score**: HP oscillation directly maps to the "almost died but recovered" feeling that creates memorable moments. Already have hp_samples at 5s intervals, so the computation is trivial -- just count sign changes. Docked on Fun because HP-only misses the *feel* of tension (enemy proximity creates tension even without HP loss).

---

### H03: Enemy Density Crescendo

**Definition**: Whether enemy count rises over the course of the run (not flat, not declining). A VS-like run should crescendo toward the end.

**Formula**: `crescendo_score = mean(enemy_count_last_3_samples) / max(mean(enemy_count_first_3_samples), 1)`

**Target**: >= 1.5 (50% more enemies at the end than the beginning)

| F | A | E | Total |
|---|---|---|-------|
| 4 | 5 | 5 | 14 |

**Why this score**: Enemy density crescendo creates visual chaos, the signature VS-like endgame feeling. Already have `enemy_count_samples` at 5s intervals. Docked on Fun because density alone does not equal fun -- if enemies are too tanky to kill, high density is frustrating, not exciting.

---

### H04: Dead Zone Map (Positional)

**Definition**: Identify 5s windows where no events occur (no fires, no kills, no pickups, no damage). Report which time segments are "dead."

**Formula**: For each 5s window in the run, count events from `feel_event_timestamps` that fall in that window. Report windows with 0 events.

**Target**: 0 dead windows after t=10s (first 10s can be slow as onboarding)

| F | A | E | Total |
|---|---|---|-------|
| 4 | 5 | 4 | 13 |

**Why this score**: Dead zones kill engagement. A player who sits for 5 seconds with nothing happening questions whether the game is working. Already have event timestamps. Slightly more complex than max-gap (need to bucket), but still straightforward. Docked on Fun because *where* the dead zone falls matters -- early dead zone (learning) is acceptable, late dead zone (broken) is not.

---

### H05: Reward Clustering Coefficient

**Definition**: Measure whether rewards (XP pickups, level-ups) arrive in satisfying clusters or are monotonously uniform. Casino psychology shows that clustered rewards create more excitement than evenly-spaced ones.

**Formula**: Standard deviation of inter-reward intervals. Too low = boring uniform spacing. Too high = feast-or-famine.

**Target**: StdDev of level-up intervals between 3.0 and 10.0 seconds

| F | A | E | Total |
|---|---|---|-------|
| 4 | 4 | 4 | 12 |

**Why this score**: Variable reward timing is the backbone of VS-like addiction (the "slot machine" effect from Galante's casino background). Level-up timestamps are already tracked. Need to compute StdDev of intervals which is moderate complexity. Docked on Fun because clustering can also mean "too many level-ups at once = menu fatigue."

---

### H06: Kill-to-Threat Ratio per Stage

**Definition**: In each stage (1=vulnerability, 2=growth, 3=crisis), compute the ratio of kills to damage-taken events. A healthy run should show the ratio improving over time (getting better at killing relative to being hit).

**Formula**: `ktr_stage[s] = kills_in_stage[s] / max(damage_in_stage[s], 1)`

**Target**: Stage 1 KTR < Stage 2 KTR < Stage 3 KTR (improving mastery)

| F | A | E | Total |
|---|---|---|-------|
| 3 | 3 | 3 | 9 |

**Why this score**: Captures the "I'm getting better" feeling. But requires splitting all events by stage timestamp, which adds complexity. And for autotest (bot player), the ratio depends on bot behavior not human skill, reducing the fun signal fidelity.

---

### H07: Upgrade Impact Score

**Definition**: Measure the change in kill rate before and after each level-up. If upgrades feel impactful, kill rate should spike after each upgrade.

**Formula**: `impact = mean(kill_rate_5s_after_levelup) / mean(kill_rate_5s_before_levelup)`

**Target**: >= 1.2 (at least 20% kill rate improvement per upgrade)

| F | A | E | Total |
|---|---|---|-------|
| 5 | 2 | 2 | 9 |

**Why this score**: Directly measures whether upgrades "feel" impactful -- the core VS-like promise. But requires fine-grained kill-rate tracking per second around level-up events, which is not currently instrumented. Would need per-second kill counters and correlation with level-up timestamps.

---

### H08: Action Density Variance (Temporal Shape)

**Definition**: Instead of a single average action density, compute density per 10s window and measure the *shape* of the curve. Fun runs should have rising density with occasional dips (relief moments), not a flat line.

**Formula**: Compute events-per-second in each 10s window. Then: `shape_score = (peak_density - valley_density) / mean_density`

**Target**: 0.5-2.0 (significant contrast between peak and valley moments)

| F | A | E | Total |
|---|---|---|-------|
| 5 | 4 | 3 | 12 |

**Why this score**: This is the temporal shape that makes runs feel dynamic vs. flat. Event timestamps already exist; need windowed density calculation. Implementation requires bucketing events by 10s window and computing min/max/mean -- moderate complexity.

---

### H09: Near-Death Recovery Count

**Definition**: Number of times HP drops below 30% and then recovers above 50%. These "clutch moments" are the most memorable parts of any run.

**Formula**: Scan `hp_samples` for patterns where `hp_pct < 0.30` followed by `hp_pct > 0.50`

**Target**: 1-3 per run (zero = too easy, >3 = frustrating)

| F | A | E | Total |
|---|---|---|-------|
| 5 | 5 | 4 | 14 |

**Why this score**: Near-death recoveries are the #1 generator of "that was amazing" moments. HP samples at 5s intervals are already tracked. Logic is a simple state machine over the samples. Slight dock on Ease because the 5s sampling interval might miss sub-5s recoveries.

---

### H10: Combo Peak Satisfaction

**Definition**: The highest combo achieved during the run, and when it occurred. Higher combos = more sustained engagement. Peak combo in the second half = satisfying crescendo.

**Formula**: `best_combo` value + `best_combo_timestamp / run_duration` (temporal weighting)

**Target**: best_combo >= 8, occurring after t=30s

| F | A | E | Total |
|---|---|---|-------|
| 3 | 3 | 3 | 9 |

**Why this score**: Combos reward sustained killing, which is core VS-like engagement. But `best_combo` is already tracked while `best_combo_timestamp` is not -- needs adding. And combo design is still early (fixed 2.0s window), so this metric would evolve with the mechanic.

---

### H11: First-Kill Latency

**Definition**: Time in seconds from game start to first enemy kill. Measures how quickly the game "hooks" the player.

**Formula**: `first_kill_time = min(feel_event_timestamps where event_type == "kill")`

**Target**: < 5 seconds (immediate engagement)

| F | A | E | Total |
|---|---|---|-------|
| 3 | 3 | 3 | 9 |

**Why this score**: Fast onboarding is critical for VS-likes. But event timestamps don't currently distinguish event types (kills vs. pickups vs. fires are all in the same array). Would need per-type timestamp tracking.

---

### H12: Upgrade Menu Interruption Rate

**Definition**: Ratio of time spent in upgrade menus to total game time. Too much menu time = flow-breaking.

**Formula**: `interruption_rate = upgrade_menu_total_time / game_duration`

**Target**: < 15% of total run time

| F | A | E | Total |
|---|---|---|-------|
| 4 | 5 | 5 | 14 |

**Why this score**: Menu fatigue is a known VS-like anti-pattern. Already tracked via `qm_upgrade_menu_total_time`. Pure division, trivial to compute. Docked on Fun because short menu time doesn't guarantee fun -- it just prevents anti-fun.

---

### H13: Screen Coverage Entropy (from Screenshots)

**Definition**: Analyze 10s-interval screenshots for visual entropy -- how much of the screen is "active" (non-background). Higher entropy in later screenshots = progressive visual chaos (the VS-like signature).

**Formula**: For each screenshot, compute the percentage of pixels that differ significantly from the background color. `entropy_crescendo = coverage_last_screenshot / max(coverage_first_screenshot, 0.01)`

**Target**: Entropy crescendo >= 2.0 (screen is at least 2x more active at the end)

| F | A | E | Total |
|---|---|---|-------|
| 4 | 2 | 1 | 7 |

**Why this score**: Visual chaos crescendo is THE VS-like feel signature. But requires image analysis of screenshots (pixel sampling, background subtraction) which is significant implementation work outside of GDScript. Would need a Python post-processing step.

---

### H14: Level-Up Pacing Curve Fit

**Definition**: Fit the level-up timestamps to an ideal curve and measure deviation. The ideal curve accelerates initially (early levels fast) then decelerates (late levels slow), following a sqrt-like shape.

**Formula**: `pacing_fit = 1.0 - RMSE(actual_timestamps, ideal_curve) / run_duration`

**Target**: > 0.8 (close to ideal pacing curve)

| F | A | E | Total |
|---|---|---|-------|
| 3 | 4 | 2 | 9 |

**Why this score**: Good pacing is felt, not seen. But defining the "ideal curve" is subjective and requires tuning. The math (RMSE fitting) is moderately complex. Level-up timestamps are already available.

---

### H15: Kill Streak Length Distribution

**Definition**: Analyze gaps between kills. A kill streak is consecutive kills within 1.0s of each other. Fun runs should have long kill streaks (10+) in the latter half.

**Formula**: Segment kills by 1.0s gaps. Report max streak length and when it occurred.

**Target**: max_streak >= 10, occurring after t=30s

| F | A | E | Total |
|---|---|---|-------|
| 4 | 3 | 3 | 10 |

**Why this score**: Long kill streaks = the "mowing through enemies" power fantasy peak. Requires per-kill timestamps (currently kills are counted but not individually timestamped as a separate array). Moderate implementation.

---

### H16: Damage-to-Kill Efficiency

**Definition**: Total damage dealt vs. enemies killed. Measures whether hits feel "meaningful" -- too many hits per kill (spongy enemies) feels bad.

**Formula**: `efficiency = total_kills / max(total_fires, 1)` (projectiles that actually matter)

**Target**: 0.3-0.8 (not every shot kills, but most shots contribute)

| F | A | E | Total |
|---|---|---|-------|
| 3 | 5 | 5 | 13 |

**Why this score**: Sponginess is a common complaint in VS-likes. Kill count and fire count are already tracked. Simple division. But the ratio is confounded by pierce/chain/fork mechanics where a single fire can kill multiple enemies, so the range is wide.

---

### H17: Stage Transition Impact

**Definition**: Measure whether stage transitions (1->2, 2->3) create noticeable changes in game feel metrics. A well-designed stage ramp should show clear metric shifts at transition points.

**Formula**: `impact = |density_after_transition - density_before_transition| / density_before_transition`

**Target**: >= 30% change in either enemy count or kill rate at each transition

| F | A | E | Total |
|---|---|---|-------|
| 3 | 4 | 3 | 10 |

**Why this score**: Stage transitions should feel like "something changed" -- that's their entire purpose. Enemy count samples already exist and can be compared across stage boundaries. But the metric measures system behavior, not player experience directly.

---

### H18: Surplus Events Ratio (Events Beyond Survival Needs)

**Definition**: Ratio of "bonus" events (kills beyond what's needed to survive, XP beyond what's needed to level up) to "necessary" events. Fun games make you feel like you're doing *more* than just surviving.

**Formula**: `surplus = (total_kills - damage_events) / max(damage_events, 1)` (killing more than being hit)

**Target**: >= 5.0 (killing 5x more often than being hit -- you're dominating)

| F | A | E | Total |
|---|---|---|-------|
| 4 | 5 | 5 | 14 |

**Why this score**: The feeling of surplus is what creates the power fantasy. "I'm killing so many more than are hitting me" = "I am powerful." All data already exists. Simple ratio.

---

### H19: Emotional Arc Score (Composite)

**Definition**: A composite score that evaluates the *shape* of the run against the ideal VS-like emotional arc: low tension -> rising -> crisis -> power fantasy peak.

**Formula**: Divide the run into 4 quarters. For each quarter, compute a "tension score" = `(damage_taken + enemy_count) / (kills + pickups + 1)`. The ideal shape is: Q1 medium, Q2 rising, Q3 highest, Q4 declining (mastery).

**Ideal shape**: [0.3, 0.5, 0.8, 0.4]
**Score**: 1.0 - cosine_distance(actual_shape, ideal_shape)

**Target**: >= 0.7

| F | A | E | Total |
|---|---|---|-------|
| 5 | 3 | 2 | 10 |

**Why this score**: This is the closest thing to directly measuring "fun arc." It captures the temporal shape that makes VS-likes compelling. But the formula is complex (composite tensors, cosine distance), requires bucketing all events by quarter, and the "ideal shape" needs calibration against human playtest data.

---

### H20: Run Completion Desire (Proxy)

**Definition**: If the run ended because of game-over (HP=0), were conditions "close"? A close loss makes players want to retry. A blowout loss or trivial win reduces desire.

**Formula**: If game over: `desire = 1.0 - |final_hp_pct - 0.15|` (closest to 15% HP = most exciting). If win: `desire = 1.0 - |final_hp_pct - 0.5|` (winning with ~50% HP = satisfying but not trivial).

**Target**: >= 0.7

| F | A | E | Total |
|---|---|---|-------|
| 5 | 5 | 5 | 15 |

**Why this score**: The "one more run" feeling is THE metric of VS-like fun. A close game (whether win or loss) maximizes retry desire. Final HP percentage is already tracked. The formula is a simple distance calculation. Perfect scores on all axes because it uses existing data, is trivially implemented, and directly maps to the core engagement driver.

---

## Summary Table

| # | Heuristic | F | A | E | Total |
|---|-----------|---|---|---|-------|
| H01 | Power Ratio Curve | 5 | 3 | 3 | 11 |
| H02 | Tension Oscillation Index | 4 | 5 | 5 | 14 |
| H03 | Enemy Density Crescendo | 4 | 5 | 5 | 14 |
| H04 | Dead Zone Map | 4 | 5 | 4 | 13 |
| H05 | Reward Clustering Coefficient | 4 | 4 | 4 | 12 |
| H06 | Kill-to-Threat Ratio per Stage | 3 | 3 | 3 | 9 |
| H07 | Upgrade Impact Score | 5 | 2 | 2 | 9 |
| H08 | Action Density Variance | 5 | 4 | 3 | 12 |
| H09 | Near-Death Recovery Count | 5 | 5 | 4 | 14 |
| H10 | Combo Peak Satisfaction | 3 | 3 | 3 | 9 |
| H11 | First-Kill Latency | 3 | 3 | 3 | 9 |
| H12 | Upgrade Menu Interruption Rate | 4 | 5 | 5 | 14 |
| H13 | Screen Coverage Entropy | 4 | 2 | 1 | 7 |
| H14 | Level-Up Pacing Curve Fit | 3 | 4 | 2 | 9 |
| H15 | Kill Streak Length Distribution | 4 | 3 | 3 | 10 |
| H16 | Damage-to-Kill Efficiency | 3 | 5 | 5 | 13 |
| H17 | Stage Transition Impact | 3 | 4 | 3 | 10 |
| H18 | Surplus Events Ratio | 4 | 5 | 5 | 14 |
| H19 | Emotional Arc Score | 5 | 3 | 2 | 10 |
| H20 | Run Completion Desire | 5 | 5 | 5 | 15 |

---

## Shortlist: 6

Selecting the top 6 by total score, with ties broken by Fun score:

### 1. H20: Run Completion Desire (Total: 15, F:5 A:5 E:5)

**Rationale**: Perfect score on all three axes. The "one more run" feeling is the ultimate VS-like success metric. A run that ends with the player at 15% HP (exciting loss) or 50% HP (satisfying win) maximizes engagement. Uses only `final_hp_pct` which is already tracked. Zero implementation cost.

### 2. H09: Near-Death Recovery Count (Total: 14, F:5 A:5 E:4)

**Rationale**: "I almost died but pulled through" is the most visceral gaming experience. In VS-likes, the crisis point where your build is tested (minutes 10-12 in VS, ~t=40 in Spell Cascade Stage 3) is what separates good runs from forgettable ones. HP samples already exist; just need state-machine logic over them.

### 3. H02: Tension Oscillation Index (Total: 14, F:4 A:5 E:5)

**Rationale**: Pressure-relief-pressure cycles are what distinguish an engaging run from a monotonous one. Constant escalation exhausts; constant safety bores. HP sample sign-change counting is trivially implementable with existing data.

### 4. H18: Surplus Events Ratio (Total: 14, F:4 A:5 E:5)

**Rationale**: The feeling of dominance -- killing far more than being hit -- is the power fantasy made numeric. Simple ratio, all data exists. A surplus ratio of 5+ means "I'm powerful." Below 2 means "I'm just surviving." This maps directly to whether the player feels like they're winning.

### 5. H12: Upgrade Menu Interruption Rate (Total: 14, F:4 A:5 E:5)

**Rationale**: Menu fatigue is the #1 pacing killer in VS-likes. Already tracked. A run where >20% of time is spent in menus is not fun regardless of how good the combat is. This is an anti-fun detector rather than a fun detector, but preventing anti-fun is half the battle.

### 6. H03: Enemy Density Crescendo (Total: 14, F:4 A:5 E:5)

**Rationale**: Progressive visual chaos IS the VS-like reward. If the screen looks the same at t=60 as t=10, the run lacks visual payoff. Enemy count samples already exist and the crescendo ratio is a one-line calculation.

### Why These 6 and Not Others

**Excluded despite high total**:
- H04 (Dead Zone Map, 13): Overlaps with existing Feel Scorecard dead_time metric. Would be redundant.
- H16 (Damage-to-Kill Efficiency, 13): Confounded by pierce/chain/fork. Not reliable with current attack mechanics.
- H08 (Action Density Variance, 12): Excellent concept but overlaps with H02 (Tension Oscillation) and H03 (Density Crescendo). These two already capture the temporal shape it measures.

**Excluded despite high Fun**:
- H01 (Power Ratio Curve, F:5): Needs per-window kill tracking not currently instrumented.
- H07 (Upgrade Impact Score, F:5): Needs per-second kill rate correlated with level-up timestamps. High implementation cost.
- H19 (Emotional Arc Score, F:5): Composite metric that requires defining an ideal arc shape. Better to use simpler components (H02, H03, H09) that compose into the arc implicitly.

---

## Finalists: 3

### Finalist A: H20 -- Run Completion Desire

**Why it advances**: It is the single most direct proxy for "will the player play again?" -- which is the business-critical question. A game that scores perfectly on all other metrics but has trivially easy runs (HP always at 100%) fails this test, and that failure correctly predicts player drop-off.

**Detailed definition**:
```
if game_over (HP <= 0):
    desire = 1.0 - abs(lowest_hp_pct - 0.0)
    # The more they fought before dying, the higher the desire
    # But we use damage_taken and survival_time as modifiers:
    desire = min(run_time / game_duration, 1.0) * 0.5 + (1.0 - lowest_hp_pct) * 0.5
    # Dying at t=55 with HP having been at 5% feels closer than dying at t=10

if win (survived to end):
    # Sweet spot: winning with 30-70% HP
    # Too easy (>90%) = boring. Barely survived (<20%) = stressful but exciting.
    desire = 1.0 - abs(final_hp_pct - 0.50) * 1.5
    desire = clamp(desire, 0.0, 1.0)
```

**Thresholds**:
| Score | Verdict |
|-------|---------|
| 0.8-1.0 | EXCELLENT -- "One more run" maximized |
| 0.6-0.8 | GOOD -- Engaging difficulty |
| 0.4-0.6 | WARN -- Too easy or too punishing |
| 0.0-0.4 | FAIL -- Boring or brutal |

**Limitations**: Autotest uses a bot, not a human. The bot's skill level affects final HP. But the same bot across versions provides a *relative* comparison: "did this change make the run closer or more lopsided?"

---

### Finalist B: H09 -- Near-Death Recovery Count

**Why it advances**: Near-death recoveries are the moments players talk about. "I was at 5% HP and then got a level-up that saved me" is a *story*. Games that generate stories are fun games. This metric counts story-generating moments.

**Detailed definition**:
```
var near_death_count := 0
var was_near_death := false

for sample in hp_samples:
    if sample.hp_pct < 0.30 and not was_near_death:
        was_near_death = true
    elif sample.hp_pct > 0.50 and was_near_death:
        near_death_count += 1
        was_near_death = false
```

**Thresholds**:
| Count | Verdict |
|-------|---------|
| 1-2 | EXCELLENT -- Memorable moments without frustration |
| 3 | GOOD -- Intense but manageable |
| 0 | WARN -- No tension, probably too easy |
| 4+ | FAIL -- Too stressful, player is constantly dying |

**Why not H02 (Tension Oscillation)**: H02 counts ALL HP direction changes, including minor fluctuations. H09 counts only the *dramatic* ones -- the ones that create emotional peaks. H09 is more selective and therefore more diagnostic.

**Synergy with H20**: If H20 says "desire is high" AND H09 says "there were 2 near-death recoveries," that's extremely strong evidence the run was fun. The two together are more predictive than either alone.

---

### Finalist C: H18 -- Surplus Events Ratio

**Why it advances**: This is the power fantasy thermometer. VS-likes succeed because they make the player feel overwhelmingly powerful. A surplus ratio of 10:1 (killing 10x more than being hit) feels godlike. A ratio of 2:1 feels scrappy. A ratio of 1:1 feels like a slog.

**Detailed definition**:
```
var surplus = float(feel_kill_count) / maxf(float(qm_damage_taken_count), 1.0)
```

**Thresholds**:
| Ratio | Verdict |
|-------|---------|
| 10+ | EXCELLENT -- Power fantasy achieved |
| 5-10 | GOOD -- Dominant but challenged |
| 2-5 | WARN -- Struggling more than dominating |
| <2 | FAIL -- Not a VS-like experience |

**Why not H03 (Enemy Density Crescendo)**: Density crescendo measures the *input* (how many enemies appear) while Surplus measures the *output* (how effectively the player handles them). The output is closer to the player's experience. You can have a perfect crescendo but if the player can't kill them, it's frustrating.

**Why not H12 (Upgrade Menu Interruption Rate)**: Menu interruption is an anti-fun detector, not a fun detector. It prevents bad experiences but doesn't predict good ones. Surplus actively measures the positive experience.

---

### Why These 3 Cover the Fun Space

Together, these three heuristics form a triangle that captures the complete VS-like fun experience:

```
         Run Completion Desire (H20)
         "Will they play again?"
              /          \
             /            \
            /              \
   Near-Death              Surplus Events
   Recovery (H09)          Ratio (H18)
   "Was it exciting?"      "Did they feel powerful?"
```

- **H20** captures the **outcome** -- was the run well-calibrated?
- **H09** captures the **peaks** -- were there memorable moments?
- **H18** captures the **baseline** -- was the power fantasy present?

A run that scores well on all three: ended at a satisfying difficulty level, had 1-2 heart-pounding moments, and made the player feel dominant 90% of the time. That is the VS-like ideal.

---

## THE ONE: Run Completion Desire (H20)

### Why This Is THE ONE

If you could measure only one thing about a VS-like run, **Run Completion Desire** is the correct choice. Here is the reasoning:

1. **It subsumes the others**: A run with perfect desire score (finishing at 30-70% HP after a full-length run) *requires* near-death moments (you took damage) AND surplus power (you didn't die). H20 implicitly tests H09 and H18.

2. **It is the business metric**: Player retention in VS-likes is driven entirely by "one more run." A game where every run ends in a satisfying difficulty zone retains players. A game where runs are trivially easy (100% HP) or brutally hard (instant death) loses players. H20 directly predicts retention.

3. **It is the cheapest to compute**: One subtraction and one absolute value. Uses `final_hp_pct` which is already the last entry in `hp_samples`. Zero new instrumentation needed.

4. **It is the most robust across bot behaviors**: The autotest bot is not a human, but H20 still works because it measures *game balance*, not player skill. If the bot consistently finishes at 95% HP, the game is too easy *for any player at that skill level*. If the bot consistently dies at t=15s, the game is too hard. The bot serves as a consistent "average player" proxy.

5. **It captures the quality gate's biggest blind spot**: The existing quality gate checks stability (did it crash?), balance (was damage taken?), and feel (was there dead time?). But it never asks: **"When the run ended, was the player in a state that makes them want to play again?"** This is the missing keystone.

### Implementation Spec

#### New code in SpellCascadeAutoTest.gd

Add to the `results["feel_scorecard"]` dictionary output in `_finish_test()`:

```gdscript
# --- Run Completion Desire (THE ONE feel heuristic) ---
var final_hp_pct := 1.0
if not qm_hp_samples.is_empty():
    final_hp_pct = qm_hp_samples[-1].hp_pct

var desire_score := 0.0
var desire_rating := "FAIL"

# Did the run end naturally (time ran out) or early (death)?
var survived := final_hp_pct > 0.0

if survived:
    # Sweet spot: finishing with 30-70% HP
    # Too easy (>90%): boring, no tension existed
    # Very close (<20%): exciting but potentially frustrating
    # Perfect (40-60%): satisfying challenge
    desire_score = 1.0 - absf(final_hp_pct - 0.50) * 1.5
    desire_score = clampf(desire_score, 0.0, 1.0)
else:
    # Died: score based on how far into the run they got
    # Dying at t=55 is more engaging than dying at t=10
    var run_completion := run_time / GAME_DURATION if "run_time" in results else 0.0
    # Also factor in whether they fought hard (damage taken > 0 = they were in combat)
    var fought_hard := 1.0 if qm_damage_taken_count >= 3 else 0.5
    desire_score = run_completion * 0.7 * fought_hard

if desire_score >= 0.8:
    desire_rating = "EXCELLENT"
elif desire_score >= 0.6:
    desire_rating = "GOOD"
elif desire_score >= 0.4:
    desire_rating = "WARN"
else:
    desire_rating = "FAIL"

print("[AutoTest] Run Completion Desire: %.2f (%s) [hp=%.0f%% survived=%s]" % [
    desire_score, desire_rating, final_hp_pct * 100.0, str(survived)
])
```

#### Add to results dict:

```gdscript
results["feel_scorecard"]["run_desire"] = snappedf(desire_score, 0.01)
results["feel_scorecard"]["run_desire_rating"] = desire_rating
results["feel_scorecard"]["run_survived"] = survived
results["feel_scorecard"]["final_hp_pct"] = snappedf(final_hp_pct, 0.01)
```

#### Log output format:

```
[AutoTest] === FEEL SCORECARD ===
[AutoTest] Dead Time: 2.1s (EXCELLENT)
[AutoTest] Action Density: 4.2 events/s (GOOD)
[AutoTest] Reward Frequency: 45 pickups/min (GOOD)
[AutoTest] Run Completion Desire: 0.78 (GOOD) [hp=68% survived=true]
[AutoTest] === END FEEL SCORECARD ===
```

### Calibration Notes

The sweet-spot center (50% HP for win) and the 1.5x penalty multiplier are initial values. They should be calibrated against human playtesting:

1. Run 5 autotest runs with current balance settings
2. Record desire scores
3. Have a human play 5 runs and rate "would you play again?" on 1-5 scale
4. Correlate autotest desire scores with human ratings
5. Adjust center point and penalty multiplier until r > 0.7

Until human calibration, the thresholds should be treated as ADVISORY (WARN, never NO-GO), matching the existing Feel Scorecard tier policy.

### Follow-Up Heuristics (Phase 2)

Once H20 is implemented and calibrated, add H09 (Near-Death Recovery Count) and H18 (Surplus Events Ratio) as supplementary diagnostics. Together, the three form a complete feel evaluation:

```
TIER 4: FEEL SCORECARD
  4a. Dead Time .............. EXCELLENT (existing)
  4b. Action Density ......... GOOD (existing)
  4c. Reward Frequency ....... GOOD (existing)
  4d. Run Completion Desire .. GOOD (THE ONE)
  4e. Near-Death Recoveries .. 2 (Phase 2)
  4f. Surplus Ratio .......... 8.5 (Phase 2)
```

### Files to Modify

| File | Change |
|------|--------|
| `scripts/debug/SpellCascadeAutoTest.gd` | Add desire score computation in `_finish_test()` |
| No other files | H20 uses only existing telemetry data |

---

## Appendix: Rejected Heuristics and Why

| Heuristic | Total | Rejection Reason |
|-----------|-------|-----------------|
| H06: Kill-to-Threat Ratio | 9 | Stage-splitting adds complexity; bot skill confounds results |
| H07: Upgrade Impact Score | 9 | Needs per-second kill instrumentation; high implementation cost |
| H10: Combo Peak Satisfaction | 9 | Combo system too immature; would measure combo design, not fun |
| H11: First-Kill Latency | 9 | Useful but narrow; captures only the first 5 seconds |
| H14: Level-Up Pacing Curve Fit | 9 | "Ideal curve" is subjective; calibration chicken-and-egg |
| H13: Screen Coverage Entropy | 7 | Requires image analysis pipeline; out of scope for GDScript |
| H01: Power Ratio Curve | 11 | Excellent concept but needs kill-per-window tracking |
| H05: Reward Clustering | 12 | Good metric but overlaps with existing pacing checks |
| H08: Action Density Variance | 12 | Overlaps with H02 and H03; redundant in shortlist |
| H15: Kill Streak Distribution | 10 | Needs per-kill timestamps; moderate cost for moderate signal |
| H17: Stage Transition Impact | 10 | Measures system design, not player experience |
| H04: Dead Zone Map | 13 | Redundant with existing dead_time metric |
| H16: Damage-to-Kill Efficiency | 13 | Confounded by pierce/chain/fork mechanics |

## References

- `docs/vs-like-game-design-research.md` -- VS-like design principles and the power fantasy arc
- `docs/feel-scorecard-20-6-3-1.md` -- Existing Feel Scorecard (dead time, action density, reward frequency)
- `docs/reward-curve-stage-transition-20-6-3-1.md` -- Stage ramp and pacing data
- `docs/v04-stage-ramp-spec-20-6-3-1.md` -- 3-Act structure specification
- `GAME_QUALITY_FRAMEWORK.md` -- Full quality evaluation framework
- `scripts/debug/SpellCascadeAutoTest.gd` -- AutoTest implementation (telemetry source)
