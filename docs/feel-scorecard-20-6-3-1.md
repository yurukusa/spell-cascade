# Feel Scorecard Design: 20→6→3→1

Date: 2026-02-16
Task: explore-spell-cascade-feel-scorecard-20-6-3-1

## Problem
Quality Gate catches stability and balance issues, but not "feel" issues.
A game can be stable and balanced yet feel lifeless.
Need automated proxies for human "feel" judgment.

## 20 Candidate Metrics (brainstorm)

1. **Action Density** — events per second (fires + kills + pickups)
2. **Audio Coverage** — % of frames with active audio
3. **Dead Time** — consecutive seconds with 0 events
4. **Feedback Latency** — ms between action and visual/audio response
5. **Screen Occupation** — % of screen with active entities
6. **Color Variety** — unique hues in screenshot sample
7. **Input Responsiveness** — ms between input and character movement
8. **VFX Count** — active visual effects per frame
9. **Reward Frequency** — XP pickups per minute
10. **Power Growth Rate** — DPS at T=0 vs T=30 vs T=60
11. **Difficulty Ramp Smoothness** — standard deviation of HP delta per 10s window
12. **Upgrade Impact** — DPS change after each upgrade choice
13. **Kill Satisfaction** — kill rate during combo windows
14. **Tension Oscillation** — HP volatility (high/low swings)
15. **Exploration Pressure** — distance moved per minute
16. **Cognitive Load** — upgrade menus per minute
17. **Session Pacing** — time to first kill, first levelup, first boss
18. **Near-Death Events** — times HP drops below 25%
19. **Sound Event Density** — distinct sound plays per second
20. **Visual Noise** — entity count at peak moments

## Narrowed to 6

### Cut reasons:
- 4 (Feedback Latency): Godot's frame-based, can't measure sub-frame
- 6 (Color Variety): Screenshot analysis too complex for automated gate
- 7 (Input Responsiveness): Same as latency, Godot limitation
- 8 (VFX Count): Would need VFX tracking system, not yet implemented
- 5 (Screen Occupation): Requires image analysis
- 11 (Difficulty Smoothness): Quality Gate tier2 already covers this
- 12 (Upgrade Impact): Hard to isolate (confounding variables)
- 15 (Exploration Pressure): Movement is input-dependent, AutoTest uses WASD randomly
- 16 (Cognitive Load): Controlled by upgrade_schedule, not a feel metric
- 20 (Visual Noise): Overlaps with density metrics

### Kept (automatable via AutoTest telemetry):
1. **Action Density** — events/sec (fires + hits + kills + pickups + levelups)
2. **Dead Time** — max consecutive seconds with 0 player-impacting events
3. **Reward Frequency** — XP pickups per minute
4. **Power Growth Rate** — DPS ratio T=60/T=0
5. **Tension Oscillation** — HP swing count (times HP changes direction)
6. **Session Pacing Milestones** — time to first kill, levelup, upgrade, boss

## Narrowed to 3

### Cut reasons:
- 4 (Power Growth): Requires DPS tracking per slot — complex, deferred
- 5 (Tension Oscillation): HP swings are rare in AutoTest (bot doesn't move optimally)
- 6 (Session Milestones): Partially captured by quality gate tier2 pacing

### THE THREE:
1. **Action Density** (events/sec)
   - MEASURE: `(total_fires + kill_count + xp_pickups + level_ups) / test_duration`
   - GOOD: 3-8 events/sec (engaging without overwhelming)
   - BAD: <1 (boring), >15 (chaos/noise)
   - IMPLEMENTATION: Sum telemetry counters in AutoTest, divide by 60s

2. **Dead Time** (max gap seconds)
   - MEASURE: Longest window with 0 fires, 0 kills, 0 pickups
   - GOOD: <5 seconds (always something happening)
   - BAD: >10 seconds (player checks if game froze)
   - IMPLEMENTATION: Track timestamps of all events, find max gap

3. **Reward Frequency** (XP pickups/min)
   - MEASURE: `xp_pickup_count / (test_duration / 60)`
   - GOOD: 20-60/min (frequent dopamine, not overwhelming)
   - BAD: <10/min (sparse), >100/min (meaningless)
   - IMPLEMENTATION: Count XP pickup events in AutoTest

## THE ONE

**Dead Time** — the single most diagnostic feel metric.

Rationale:
- If Dead Time > 10s, the game *feels dead* regardless of other metrics
- It's the inverse of engagement: the longer the gap, the more likely a player closes the tab
- It's simple to measure: just track the max gap between any player-relevant events
- It catches both balance issues (enemies too sparse) and reward issues (no pickups)
- VS-like games succeed when there is ALWAYS something happening

Implementation:
```gdscript
# In AutoTest: track all event timestamps
var event_timestamps: Array[float] = []

# On any event (fire, kill, pickup, levelup, damage):
event_timestamps.append(elapsed)

# At end: calculate max gap
var max_gap := 0.0
for i in range(1, event_timestamps.size()):
    max_gap = maxf(max_gap, event_timestamps[i] - event_timestamps[i-1])
```

Thresholds:
| Dead Time | Verdict |
|-----------|---------|
| 0-3s | EXCELLENT |
| 3-5s | GOOD |
| 5-10s | WARN |
| 10s+ | FAIL |

## Integration Plan
Add feel scorecard as optional TIER 4 in quality-gate.sh:
- TIER 1: Stability (crash/playability)
- TIER 2: Balance Band (difficulty/pacing)
- TIER 3: Regression (baseline comparison)
- **TIER 4: Feel Scorecard (dead_time, action_density, reward_freq)**

TIER 4 is advisory-only (WARN, never NO-GO) since feel thresholds need
calibration against human playtests.
