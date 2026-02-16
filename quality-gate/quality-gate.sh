#!/usr/bin/env bash
# Spell Cascade Autonomous Quality Gate
# Usage: quality-gate.sh [--baseline path] [--results path] [--skip-run]
# Exit 0 = GO or CONDITIONAL, Exit 1 = NO-GO

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
THRESHOLDS="$SCRIPT_DIR/thresholds.json"
BASELINE_DIR="$SCRIPT_DIR/baselines"
RESULTS_PATH="/tmp/godot_auto_test/results.json"
LOG_FILE="$SCRIPT_DIR/gate-log.jsonl"
SKIP_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --baseline) BASELINE_DIR="$2"; shift 2 ;;
        --results) RESULTS_PATH="$2"; shift 2 ;;
        --skip-run) SKIP_RUN=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$BASELINE_DIR"

# jq existence check
if ! command -v jq &>/dev/null; then
    echo "[QualityGate] ERROR: jq not found. Install with: sudo apt install jq"
    exit 1
fi

# Run SpellCascadeAutoTest if not skipping
if [[ "$SKIP_RUN" == false ]]; then
    echo "[QualityGate] Running SpellCascadeAutoTest (60s)..."
    AUTOTEST_SCRIPT="scripts/debug/SpellCascadeAutoTest.gd"
    PROJECT_CFG="$PROJECT_DIR/project.godot"

    # Temporarily add SpellCascadeAutoTest to autoload
    if ! grep -q "SpellCascadeAutoTest" "$PROJECT_CFG"; then
        # Find last autoload entry (lines like Key="*res://...") and insert after it
        LAST_AUTOLOAD_LINE=$(grep -n '^[A-Za-z].*="\*res://' "$PROJECT_CFG" | tail -1 | cut -d: -f1)
        if [[ -n "$LAST_AUTOLOAD_LINE" ]]; then
            sed -i "${LAST_AUTOLOAD_LINE}a SpellCascadeAutoTest=\"*res://${AUTOTEST_SCRIPT}\"" "$PROJECT_CFG"
        fi
        AUTOTEST_ADDED=true
        echo "[QualityGate] Added SpellCascadeAutoTest to autoload"
    fi

    # Run with xvfb
    timeout 90 xvfb-run -a godot --path "$PROJECT_DIR" --quit-after 70 2>&1 || true

    # Remove SpellCascadeAutoTest from autoload
    if [[ "${AUTOTEST_ADDED:-false}" == true ]]; then
        sed -i '/SpellCascadeAutoTest/d' "$PROJECT_CFG"
        echo "[QualityGate] Removed SpellCascadeAutoTest from autoload"
    fi

    echo "[QualityGate] AutoTest complete."
fi

# Check results exist
if [[ ! -f "$RESULTS_PATH" ]]; then
    echo "[QualityGate] ERROR: results.json not found at $RESULTS_PATH"
    echo "[QualityGate] VERDICT: NO-GO (no results)"
    exit 1
fi

echo "[QualityGate] === SPELL CASCADE QUALITY GATE ==="
echo "[QualityGate] Results: $RESULTS_PATH"

# Parse results
RESULTS=$(cat "$RESULTS_PATH")

# Helper: read from results JSON
jq_r() { echo "$RESULTS" | jq -r "$1" 2>/dev/null; }
jq_n() { echo "$RESULTS" | jq "$1" 2>/dev/null || echo "0"; }

# Read thresholds
T=$(cat "$THRESHOLDS")
jq_t() { echo "$T" | jq "$1" 2>/dev/null || echo "0"; }

VERDICT="GO"
REASONS=()
TIER1_PASS=true
TIER2_CHECKS=0
TIER2_PASSES=0

# ========== TIER 1: STABILITY ==========
echo "[QualityGate] --- TIER 1: STABILITY ---"

# Check: script errors (from test output, not in results.json directly)
PASS_VAL=$(jq_r '.pass')
TOTAL_FIRES=$(jq_n '.telemetry.total_fires')
LEVEL_UPS=$(jq_n '.telemetry.level_ups')
PLAYER_LEVEL=$(jq_n '.telemetry.player_level // 0')

# pass field check
if [[ "$PASS_VAL" != "true" ]]; then
    echo "[QualityGate]   pass=false → FAIL"
    TIER1_PASS=false
    REASONS+=("stability_pass_false")
else
    echo "[QualityGate]   pass=true → OK"
fi

# total fires check
MIN_FIRES=$(jq_t '.tier1_stability.min_total_fires')
if [[ "$TOTAL_FIRES" -lt "$MIN_FIRES" ]]; then
    echo "[QualityGate]   total_fires=$TOTAL_FIRES (want>=$MIN_FIRES) → FAIL"
    TIER1_PASS=false
    REASONS+=("stability_no_fires")
else
    echo "[QualityGate]   total_fires=$TOTAL_FIRES → OK"
fi

# level ups check
MIN_LU=$(jq_t '.tier1_stability.min_level_ups')
if [[ "$LEVEL_UPS" -lt "$MIN_LU" ]]; then
    echo "[QualityGate]   level_ups=$LEVEL_UPS (want>=$MIN_LU) → FAIL"
    TIER1_PASS=false
    REASONS+=("stability_no_levelups")
else
    echo "[QualityGate]   level_ups=$LEVEL_UPS → OK"
fi

if [[ "$TIER1_PASS" == true ]]; then
    echo "[QualityGate] TIER1: PASS"
else
    echo "[QualityGate] TIER1: FAIL"
    VERDICT="NO-GO"
fi

# ========== TIER 2: BALANCE BAND ==========
echo "[QualityGate] --- TIER 2: BALANCE BAND ---"

# Read quality metrics
DMG_TAKEN=$(jq_n '.quality_metrics.damage_taken_count')
LOWEST_HP=$(jq_r '.quality_metrics.lowest_hp_pct')
AVG_INTERVAL=$(jq_r '.quality_metrics.avg_levelup_interval')
FATIGUE=$(jq_r '.quality_metrics.fatigue_rating')
DIFF_RATING=$(jq_r '.quality_metrics.difficulty_rating')

# Enemy density: peak and average
PEAK_ENEMIES=$(echo "$RESULTS" | jq '[.quality_metrics.enemy_count_samples[].count] | max // 0' 2>/dev/null || echo "0")
AVG_ENEMIES=$(echo "$RESULTS" | jq '[.quality_metrics.enemy_count_samples[].count] | add / length // 0' 2>/dev/null || echo "0")

# Levelup gap check (min time between consecutive levelups)
MIN_GAP=$(echo "$RESULTS" | jq '
  .quality_metrics.levelup_timestamps as $ts |
  if ($ts | length) < 2 then 999
  else [range(1; $ts | length)] | map($ts[.] - $ts[. - 1]) | min
  end
' 2>/dev/null || echo "999")

# Sub-check 1: Difficulty Floor
TIER2_CHECKS=$((TIER2_CHECKS + 1))
MIN_DMG=$(jq_t '.tier2_balance.difficulty_floor.min_damage_taken')
if [[ "$DMG_TAKEN" -ge "$MIN_DMG" ]]; then
    echo "[QualityGate]   Difficulty Floor: PASS (damage=$DMG_TAKEN)"
    TIER2_PASSES=$((TIER2_PASSES + 1))
else
    echo "[QualityGate]   Difficulty Floor: WARN (damage=$DMG_TAKEN, want>=$MIN_DMG)"
    REASONS+=("difficulty_floor_warn")
fi

# Sub-check 2: Difficulty Ceiling
TIER2_CHECKS=$((TIER2_CHECKS + 1))
MIN_HP_PCT=$(jq_t '.tier2_balance.difficulty_ceiling.min_lowest_hp_pct')
CEILING_PASS=true
# Use awk for float comparison
if echo "$LOWEST_HP $MIN_HP_PCT" | awk '{exit ($1 >= $2) ? 0 : 1}'; then
    echo "[QualityGate]   Difficulty Ceiling: PASS (lowest_hp=${LOWEST_HP})"
    TIER2_PASSES=$((TIER2_PASSES + 1))
else
    echo "[QualityGate]   Difficulty Ceiling: FAIL (lowest_hp=${LOWEST_HP}, want>=${MIN_HP_PCT})"
    CEILING_PASS=false
    REASONS+=("difficulty_ceiling_fail")
fi

# Sub-check 3: Pacing
TIER2_CHECKS=$((TIER2_CHECKS + 1))
MIN_INT=$(jq_t '.tier2_balance.pacing.min_avg_interval')
MAX_INT=$(jq_t '.tier2_balance.pacing.max_avg_interval')
MIN_LU_GAP=$(jq_t '.tier2_balance.pacing.min_gap_between_levelups')
PACING_OK=true
PACING_DETAIL=""

if echo "$AVG_INTERVAL $MIN_INT" | awk '{exit ($1 >= $2) ? 0 : 1}'; then
    if echo "$AVG_INTERVAL $MAX_INT" | awk '{exit ($1 <= $2) ? 0 : 1}'; then
        PACING_DETAIL="avg=${AVG_INTERVAL}s in [${MIN_INT}-${MAX_INT}]"
    else
        PACING_OK=false
        PACING_DETAIL="avg=${AVG_INTERVAL}s > max=${MAX_INT}s (too slow)"
    fi
else
    PACING_OK=false
    PACING_DETAIL="avg=${AVG_INTERVAL}s < min=${MIN_INT}s (too frequent)"
fi

# Also check min gap
if echo "$MIN_GAP $MIN_LU_GAP" | awk '{exit ($1 >= $2) ? 0 : 1}'; then
    : # gap OK
else
    PACING_OK=false
    PACING_DETAIL="$PACING_DETAIL, min_gap=${MIN_GAP}s < ${MIN_LU_GAP}s (burst)"
fi

if [[ "$PACING_OK" == true ]]; then
    echo "[QualityGate]   Pacing: PASS ($PACING_DETAIL)"
    TIER2_PASSES=$((TIER2_PASSES + 1))
else
    echo "[QualityGate]   Pacing: WARN ($PACING_DETAIL)"
    REASONS+=("pacing_warn")
fi

# Sub-check 4: Density
TIER2_CHECKS=$((TIER2_CHECKS + 1))
MIN_PEAK=$(jq_t '.tier2_balance.density.min_peak_enemies')
MIN_AVG_E=$(jq_t '.tier2_balance.density.min_avg_enemies')
DENSITY_OK=true

if [[ "$PEAK_ENEMIES" -ge "$MIN_PEAK" ]]; then
    if echo "$AVG_ENEMIES $MIN_AVG_E" | awk '{exit ($1 >= $2) ? 0 : 1}'; then
        echo "[QualityGate]   Density: PASS (peak=$PEAK_ENEMIES, avg=$AVG_ENEMIES)"
        TIER2_PASSES=$((TIER2_PASSES + 1))
    else
        DENSITY_OK=false
        echo "[QualityGate]   Density: WARN (avg=$AVG_ENEMIES < min=$MIN_AVG_E)"
    fi
else
    DENSITY_OK=false
    echo "[QualityGate]   Density: WARN (peak=$PEAK_ENEMIES < min=$MIN_PEAK)"
fi
if [[ "$DENSITY_OK" != true ]]; then
    REASONS+=("density_warn")
fi

# TIER2 aggregate
PASS_THRESHOLD=$(jq_t '.tier2_balance.pass_threshold')
NOGO_CEILING=$(jq_t '.tier2_balance.nogo_on_ceiling_fail')

echo "[QualityGate]   Balance: $TIER2_PASSES/$TIER2_CHECKS PASS (threshold: $PASS_THRESHOLD)"

if [[ "$NOGO_CEILING" == "true" && "$CEILING_PASS" == false ]]; then
    echo "[QualityGate] TIER2: NO-GO (ceiling fail is fatal)"
    VERDICT="NO-GO"
elif [[ "$TIER2_PASSES" -ge "$PASS_THRESHOLD" ]]; then
    echo "[QualityGate] TIER2: PASS"
else
    echo "[QualityGate] TIER2: CONDITIONAL"
    if [[ "$VERDICT" != "NO-GO" ]]; then
        VERDICT="CONDITIONAL"
    fi
fi

# ========== TIER 3: REGRESSION ==========
echo "[QualityGate] --- TIER 3: REGRESSION ---"

LATEST_BASELINE="$BASELINE_DIR/latest.json"
if [[ -f "$LATEST_BASELINE" ]]; then
    echo "[QualityGate] Comparing against baseline: $LATEST_BASELINE"
    WARN_PCT=$(jq_t '.tier3_regression.warn_threshold_pct')
    NOGO_PCT=$(jq_t '.tier3_regression.nogo_threshold_pct')

    # Compare key metrics
    BL_DMG=$(jq -r '.quality_metrics.damage_taken_count' "$LATEST_BASELINE" 2>/dev/null || echo "0")
    BL_PEAK=$(jq '[.quality_metrics.enemy_count_samples[].count] | max // 0' "$LATEST_BASELINE" 2>/dev/null || echo "0")
    BL_INTERVAL=$(jq -r '.quality_metrics.avg_levelup_interval' "$LATEST_BASELINE" 2>/dev/null || echo "0")

    REGRESS_WARNS=0
    REGRESS_NOGOS=0

    # Density regression (lower is worse)
    if [[ "$BL_PEAK" -gt 0 && "$PEAK_ENEMIES" -gt 0 ]]; then
        DELTA_PCT=$(echo "$PEAK_ENEMIES $BL_PEAK" | awk '{printf "%.0f", (1 - $1/$2) * 100}')
        if [[ "$DELTA_PCT" -gt "$NOGO_PCT" ]]; then
            echo "[QualityGate]   Peak enemies regressed ${DELTA_PCT}% → NO-GO"
            REGRESS_NOGOS=$((REGRESS_NOGOS + 1))
        elif [[ "$DELTA_PCT" -gt "$WARN_PCT" ]]; then
            echo "[QualityGate]   Peak enemies regressed ${DELTA_PCT}% → WARN"
            REGRESS_WARNS=$((REGRESS_WARNS + 1))
        else
            echo "[QualityGate]   Peak enemies: ${PEAK_ENEMIES} (baseline: ${BL_PEAK}) → OK"
        fi
    fi

    if [[ "$REGRESS_NOGOS" -gt 0 ]]; then
        echo "[QualityGate] TIER3: NO-GO ($REGRESS_NOGOS regressions)"
        VERDICT="NO-GO"
        REASONS+=("regression_nogo")
    elif [[ "$REGRESS_WARNS" -gt 0 ]]; then
        echo "[QualityGate] TIER3: WARN ($REGRESS_WARNS regressions)"
        if [[ "$VERDICT" != "NO-GO" ]]; then
            VERDICT="CONDITIONAL"
        fi
        REASONS+=("regression_warn")
    else
        echo "[QualityGate] TIER3: PASS"
    fi
else
    echo "[QualityGate] TIER3: SKIP (no baseline found)"
fi

# ========== VERDICT ==========
echo "[QualityGate] === VERDICT: $VERDICT ==="
if [[ ${#REASONS[@]} -gt 0 ]]; then
    echo "[QualityGate] Reasons: $(IFS=', '; echo "${REASONS[*]}")"
fi

# Save baseline on GO
if [[ "$VERDICT" == "GO" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    cp "$RESULTS_PATH" "$BASELINE_DIR/baseline-$TIMESTAMP.json"
    cp "$RESULTS_PATH" "$LATEST_BASELINE"
    echo "[QualityGate] Baseline saved: baseline-$TIMESTAMP.json"
fi

# Append to log
LOG_ENTRY=$(jq -n \
    --arg verdict "$VERDICT" \
    --arg timestamp "$(date -Is)" \
    --arg reasons "$(IFS=','; echo "${REASONS[*]}")" \
    --argjson tier2_passes "$TIER2_PASSES" \
    --argjson tier2_checks "$TIER2_CHECKS" \
    --argjson damage "$DMG_TAKEN" \
    --arg lowest_hp "$LOWEST_HP" \
    --arg avg_interval "$AVG_INTERVAL" \
    --argjson peak_enemies "$PEAK_ENEMIES" \
    '{timestamp: $timestamp, verdict: $verdict, tier2_score: "\($tier2_passes)/\($tier2_checks)", damage_taken: $damage, lowest_hp_pct: $lowest_hp, avg_levelup_interval: $avg_interval, peak_enemies: $peak_enemies, reasons: $reasons}')
echo "$LOG_ENTRY" >> "$LOG_FILE"
echo "[QualityGate] Log appended to: $LOG_FILE"

# Exit code
if [[ "$VERDICT" == "NO-GO" ]]; then
    exit 1
else
    exit 0
fi
