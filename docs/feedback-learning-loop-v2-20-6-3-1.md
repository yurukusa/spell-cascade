# Feedback Learning Loop v2 — Spell Cascade Quality Gate Integration

Date: 2026-02-16
Status: Active
Version: v2 (20-6-3-1 heuristics integrated)

## Overview

The v2 feedback learning loop connects human playtesting feedback to automated quality gate thresholds, creating a closed-loop system where player experience insights automatically update the validation criteria for future releases.

## Feedback Classification System

All human feedback (playtesting notes, bug reports, community feedback) is classified into one of four categories using a standard prefix:

| Category | Prefix | Examples | Priority |
|----------|--------|----------|----------|
| **BUG** | BUG-N | Crashes, script errors, non-functional features | P0 (blocks release) |
| **BALANCE** | BAL-N | Difficulty too flat, XP curve too fast, enemy scaling | P1 (affects core loop) |
| **UI** | UI-N | HUD missing info, visual clarity, control feedback | P2 (affects usability) |
| **FEEL** | FEEL-N | Fun factor, engagement, emotional arc | P3 (affects retention) |

### Priority Rules

1. **BUG > BALANCE > UI > FEEL** — always address in this order
2. **Tier1 failures (stability) are always BUG-class** — they block GO verdict
3. **Tier2 failures (balance) are usually BAL-class** — they trigger CONDITIONAL verdict
4. **Tier3 failures (regression) detect unintended side effects** — they require investigation

## v0.2.3 Playtesting Feedback Example

From human playtesting session 2026-02-15:

### Feedback Classification

| Original Feedback | Classification | Quality Gate Mapping |
|-------------------|----------------|----------------------|
| "Difficulty too flat, enemies not scaling" | BAL-1 | `tier2_balance.density.min_peak_enemies` + `difficulty_floor.min_damage_taken` |
| "XP curve too fast, max level too easy" | BAL-2 | `tier2_balance.pacing.max_avg_interval` + feel heuristic H20 (run desire) |
| "+1 Projectile upgrade not working in spread mode" | BUG-1 | Tier1 stability (would fail if autotest detects no fire count increase) |
| "Spark visual too small to see" | UI-1 | Not in quality gate (visual polish) |
| "HUD doesn't show trigger conditions" | UI-2 | Not in quality gate (UX improvement) |

### 5 Judgment Axes (from playtesting)

1. **Difficulty**: Is the challenge curve satisfying? (too easy / too flat / spiky / good)
2. **Reward**: Is the pacing of level-ups engaging? (too fast / too slow / bursts / good)
3. **Intervention**: Do upgrades feel impactful? (useless / incremental / game-changing)
4. **Trigger**: Are trigger conditions clear and reliable? (broken / unclear / working)
5. **Visual**: Is combat readable and satisfying? (can't see hits / unclear / chaotic-good)

These axes map to quality gate tiers:
- **Difficulty + Reward** → Tier2 Balance Band
- **Intervention** → Feel Heuristic H07 (Upgrade Impact Score, Phase 2)
- **Trigger** → Tier1 Stability (functional tests)
- **Visual** → Not in quality gate (subjective, requires human review)

## Threshold Update Process

When feedback is classified as BAL-class (balance issue):

### Step 1: Identify the affected metric

Example: "XP too fast" → affects `tier2_balance.pacing.max_avg_interval`

Current threshold (from `thresholds.json`):
```json
"pacing": {
  "min_avg_interval": 8.0,
  "max_avg_interval": 35.0,
  "min_gap_between_levelups": 2.0
}
```

### Step 2: Calculate new threshold from desired behavior

Design intent: "Players should level up every 15-25 seconds on average"

Proposed change:
```json
"pacing": {
  "min_avg_interval": 15.0,  // was 8.0
  "max_avg_interval": 25.0,  // was 35.0
  "min_gap_between_levelups": 5.0  // was 2.0
}
```

### Step 3: Update `thresholds.json` and document the change

```bash
# Edit thresholds.json
# Add entry to quality-gate/CHANGELOG.md:
echo "2026-02-16: Tightened pacing thresholds per BAL-2 (v0.2.3 XP too fast feedback)" >> quality-gate/CHANGELOG.md
```

### Step 4: Validate with autotest

```bash
cd ~/projects/spell-cascade
./quality-gate/quality-gate.sh
```

Expected outcome:
- **Before fix**: Tier2 pacing WARN (avg_interval=9.2s < min=15.0s)
- **After fix** (game tuned): Tier2 pacing PASS (avg_interval=18.5s in [15.0-25.0])

### Step 5: Record the learning

Add entry to `docs/balance-lessons.md`:
```markdown
## BAL-2: XP Curve Too Fast (v0.2.3 → v0.2.4)

**Symptom**: Players reaching max level with 15+ seconds remaining. No late-game challenge.

**Root Cause**: `level_thresholds` array scaled too slowly (linear instead of exponential).

**Fix**: Changed level curve from `base + (level * 5)` to `base * pow(1.4, level)`. Levels 8-10 now require 2-3x more XP.

**Threshold Update**: Increased `pacing.min_avg_interval` from 8.0 to 15.0 to detect this pattern automatically.

**Result**: v0.2.4 autotest shows avg_interval=18.2s (PASS), human playtest confirms better endgame pacing.
```

## How Each Category Connects to Quality Gate

### BUG → Tier1 Stability

| Feedback Type | Quality Gate Check | Example |
|---------------|-------------------|---------|
| Script errors | `pass=false` | "Getting null reference in tower.gd" |
| Feature not working | `min_total_fires < threshold` | "+1 Projectile not firing" |
| Game doesn't start | `exit_code != 0` | "Crashes on launch" |

**Action**: Fix immediately. Tier1 failure = NO-GO verdict. No release until green.

### BALANCE → Tier2 Balance Band

| Feedback Type | Quality Gate Check | Example |
|---------------|-------------------|---------|
| Too easy | `difficulty_floor.min_damage_taken` | "Never lost HP" |
| Too hard | `difficulty_ceiling.min_lowest_hp_pct` | "Died in 10 seconds" |
| Pacing off | `pacing.min/max_avg_interval` | "Level-ups too frequent/slow" |
| Density wrong | `density.min_peak_enemies` | "Screen always empty/too crowded" |

**Action**: Tune game parameters (XP curve, enemy spawn rates, damage scaling). Update thresholds to match new target balance.

**Note**: Tier2 failures produce CONDITIONAL verdict, not NO-GO. They require judgment.

### UI → Not in Quality Gate

UI issues are tracked separately in `docs/ui-polish-backlog.md`. They do not affect the quality gate verdict.

**Rationale**: UI polish is subjective and cannot be reliably auto-evaluated. Human review required.

### FEEL → Tier4 Feel Scorecard (Advisory)

| Feedback Type | Quality Gate Check | Example |
|---------------|-------------------|---------|
| "Boring" | Feel Heuristic H20 (Run Completion Desire) | "Runs too easy, no tension" |
| "Unfair" | Feel Heuristic H09 (Near-Death Recovery) | "Die instantly with no warning" |
| "Weak power fantasy" | Feel Heuristic H18 (Surplus Events Ratio) | "Feels like a slog, not dominating" |

**Action**: FEEL issues produce WARN ratings, never NO-GO. They inform design iteration but do not block releases.

## Threshold Evolution Strategy

### Conservative Start (Current State)

- Tier1: Strict (must crash-free, must produce fires/level-ups)
- Tier2: Permissive (50% pass rate = GO)
- Tier3: WARN-only (no NO-GO on regression until baseline stable)

### Progressive Tightening

As the game matures:
1. Tier2 `pass_threshold` increases from 3/4 to 4/4 (all balance checks must pass)
2. Tier3 `nogo_threshold_pct` decreases from 50% to 25% (regressions become blocking)
3. Feel Scorecard promotes from ADVISORY to CONDITIONAL (WARN → blocks merge)

This mirrors software testing maturity:
- **Alpha** (now): stability only
- **Beta** (v0.5+): stability + balance
- **Launch** (v1.0+): stability + balance + feel + regression

## Automation Hooks

### Git Pre-Commit Hook

Already exists at `.git/hooks/pre-commit`:
```bash
#!/usr/bin/env bash
# Run quality gate before allowing commit
~/projects/spell-cascade/quality-gate/quality-gate.sh --skip-run || {
  echo "[PreCommit] Quality gate FAILED. Fix issues before committing."
  exit 1
}
```

**Note**: Uses `--skip-run` to avoid 60s autotest on every commit. Validates against cached results.

### CI/CD Pipeline (Future)

When CI is set up:
```yaml
# .github/workflows/quality-gate.yml
on: [push, pull_request]
jobs:
  quality_gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Godot
        run: |
          wget https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
          unzip Godot_v4.3-stable_linux.x86_64.zip
          sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
      - name: Run Quality Gate
        run: ./quality-gate/quality-gate.sh
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: autotest-results
          path: /tmp/godot_auto_test/results.json
```

## Feedback → Threshold Update Checklist

When new feedback arrives:

- [ ] Classify into BUG/BAL/UI/FEEL
- [ ] Assign priority (P0-P3)
- [ ] Identify affected quality gate metric (if any)
- [ ] Calculate new threshold from design intent
- [ ] Update `thresholds.json`
- [ ] Document change in `quality-gate/CHANGELOG.md`
- [ ] Run `quality-gate.sh` to validate
- [ ] Record lesson in `docs/balance-lessons.md`
- [ ] Add regression test case if BUG-class

## Integration Status

| Tier | Name | Automation Level | Human Input Required |
|------|------|-----------------|---------------------|
| **Tier1** | Stability | Fully automated | None (objective: does it crash?) |
| **Tier2** | Balance | Partially automated | Threshold tuning from playtesting |
| **Tier3** | Regression | Baseline accumulation | Initial baseline validation |
| **Tier4** | Feel | Advisory only | Heuristic calibration (H20 center point) |

### Tier2 Partial Automation Details

Tier2 is "partially automated" because:
1. **The checks run automatically** — no human needed to measure density/pacing/damage
2. **The thresholds require human judgment** — "Is 8s too fast for level-ups?" needs design intent
3. **The verdict is objective** — once thresholds are set, the gate either passes or fails

**Process**: Human playtesting → identifies imbalance → updates threshold → autotest validates fix

### Tier4 Feel Scorecard Calibration

The Feel Scorecard (H20, H09, H18) requires one-time calibration:
1. Run 5 autotest runs, record feel scores
2. Run 5 human playtests, record subjective fun ratings (1-5 scale)
3. Correlate autotest scores with human ratings
4. Adjust heuristic parameters (e.g., H20 sweet spot center) until correlation > 0.7

**After calibration**, feel scoring is fully automated. Recalibrate only when major balance changes occur.

## References

- `quality-gate/quality-gate.sh` — 3-tier autonomous quality gate implementation
- `quality-gate/thresholds.json` — all threshold values
- `docs/feel-autoeval-heuristics-20-6-3-1.md` — 20 heuristics analysis, 6 → 3 → 1 selection
- `scripts/debug/SpellCascadeAutoTest.gd` — telemetry source for quality metrics
- `docs/balance-lessons.md` — historical record of balance changes (to be created)
