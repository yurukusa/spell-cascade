#!/usr/bin/env bash
# Game Factory Pipeline Orchestrator v1
#
# Single command to run the full quality pipeline:
#   1. Run SpellCascadeAutoTest (via quality-gate.sh)
#   2. Parse quality gate verdict
#   3. Extract feel scorecard
#   4. Generate markdown report
#
# Why: The game factory needs a single entry point that produces a
# machine-readable verdict + human-readable report. quality-gate.sh
# handles the autotest run and 3-tier evaluation; this script adds
# the feel scorecard, report generation, and pipeline summary.
#
# Usage:
#   tools/pipeline-orchestrator.sh                  # Full pipeline
#   tools/pipeline-orchestrator.sh --skip-run       # Use existing results.json
#   tools/pipeline-orchestrator.sh --report-only    # Just generate report from latest results
#   tools/pipeline-orchestrator.sh --json           # Output JSON summary (for CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
QG_DIR="$PROJECT_DIR/quality-gate"
QG_SCRIPT="$QG_DIR/quality-gate.sh"
RESULTS_PATH="/tmp/godot_auto_test/results.json"
REPORTS_DIR="$PROJECT_DIR/reports"
SKIP_RUN=false
REPORT_ONLY=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-run) SKIP_RUN=true; shift ;;
        --report-only) REPORT_ONLY=true; SKIP_RUN=true; shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        --results) RESULTS_PATH="$2"; shift 2 ;;
        -h|--help)
            echo "Game Factory Pipeline Orchestrator v1"
            echo ""
            echo "Usage: pipeline-orchestrator.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-run      Use existing results.json (skip autotest)"
            echo "  --report-only   Only generate report from latest results"
            echo "  --json          Output JSON summary to stdout"
            echo "  --results PATH  Path to results.json"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$REPORTS_DIR"

# jq is required
if ! command -v jq &>/dev/null; then
    echo "[Pipeline] ERROR: jq not found"
    exit 1
fi

# When --json, redirect human-readable output to stderr so only JSON hits stdout
# This function replaces echo for all pipeline messages
log() {
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "$@" >&2
    else
        echo "$@"
    fi
}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$REPORTS_DIR/report-$TIMESTAMP.md"

log "[Pipeline] =========================================="
log "[Pipeline]  Game Factory Pipeline Orchestrator v1"
log "[Pipeline] =========================================="
log "[Pipeline] Time: $(date -Is)"
log "[Pipeline] Project: $PROJECT_DIR"

# ===== STEP 1: Run Quality Gate =====
QG_VERDICT="UNKNOWN"
QG_OUTPUT=""
QG_EXIT=0

if [[ "$REPORT_ONLY" == false ]]; then
    log ""
    log "[Pipeline] STEP 1: Quality Gate"
    log "[Pipeline] ----------------------------------------"

    QG_ARGS=()
    if [[ "$SKIP_RUN" == true ]]; then
        QG_ARGS+=("--skip-run")
    fi
    QG_ARGS+=("--results" "$RESULTS_PATH")

    # Capture quality-gate output and exit code
    QG_OUTPUT=$("$QG_SCRIPT" "${QG_ARGS[@]}" 2>&1) || QG_EXIT=$?
    log "$QG_OUTPUT"

    # Extract verdict from output
    QG_VERDICT=$(echo "$QG_OUTPUT" | grep -oP 'VERDICT: \K\S+' | tail -1 || echo "UNKNOWN")
else
    log ""
    log "[Pipeline] STEP 1: SKIPPED (report-only mode)"
    # Try to infer from latest gate log (entries may be multi-line JSON)
    if [[ -f "$QG_DIR/gate-log.jsonl" ]]; then
        QG_VERDICT=$(jq -rs '.[-1].verdict // "UNKNOWN"' "$QG_DIR/gate-log.jsonl" 2>/dev/null || echo "UNKNOWN")
    fi
fi

log ""
log "[Pipeline] Quality Gate Verdict: $QG_VERDICT"

# ===== STEP 2: Parse Results & Feel Scorecard =====
log ""
log "[Pipeline] STEP 2: Feel Scorecard"
log "[Pipeline] ----------------------------------------"

if [[ ! -f "$RESULTS_PATH" ]]; then
    log "[Pipeline] ERROR: No results.json at $RESULTS_PATH"
    log "[Pipeline] Cannot generate report without test results."
    exit 1
fi

RESULTS=$(cat "$RESULTS_PATH")

# Feel scorecard values
DEAD_TIME=$(echo "$RESULTS" | jq '.feel_scorecard.dead_time // 0' 2>/dev/null)
DEAD_RATING=$(echo "$RESULTS" | jq -r '.feel_scorecard.dead_time_rating // "N/A"' 2>/dev/null)
ACTION_DENSITY=$(echo "$RESULTS" | jq '.feel_scorecard.action_density // 0' 2>/dev/null)
ACTION_RATING=$(echo "$RESULTS" | jq -r '.feel_scorecard.action_density_rating // "N/A"' 2>/dev/null)
REWARD_FREQ=$(echo "$RESULTS" | jq '.feel_scorecard.reward_frequency // 0' 2>/dev/null)
REWARD_RATING=$(echo "$RESULTS" | jq -r '.feel_scorecard.reward_frequency_rating // "N/A"' 2>/dev/null)
RUN_DESIRE=$(echo "$RESULTS" | jq '.feel_scorecard.run_desire // 0' 2>/dev/null)
DESIRE_RATING=$(echo "$RESULTS" | jq -r '.feel_scorecard.run_desire_rating // "N/A"' 2>/dev/null)
FINAL_HP=$(echo "$RESULTS" | jq '.feel_scorecard.final_hp_pct // 0' 2>/dev/null)
SURVIVED=$(echo "$RESULTS" | jq -r '.feel_scorecard.run_survived // false' 2>/dev/null)
KILL_COUNT=$(echo "$RESULTS" | jq '.feel_scorecard.kill_count // 0' 2>/dev/null)
TOTAL_EVENTS=$(echo "$RESULTS" | jq '.feel_scorecard.total_events // 0' 2>/dev/null)

# Quality metrics
DMG_TAKEN=$(echo "$RESULTS" | jq '.quality_metrics.damage_taken_count // 0' 2>/dev/null)
LOWEST_HP=$(echo "$RESULTS" | jq '.quality_metrics.lowest_hp_pct // 0' 2>/dev/null)
DIFF_RATING=$(echo "$RESULTS" | jq -r '.quality_metrics.difficulty_rating // "N/A"' 2>/dev/null)
FATIGUE=$(echo "$RESULTS" | jq -r '.quality_metrics.fatigue_rating // "N/A"' 2>/dev/null)
AVG_INTERVAL=$(echo "$RESULTS" | jq '.quality_metrics.avg_levelup_interval // 0' 2>/dev/null)

# Telemetry
PLAYER_LEVEL=$(echo "$RESULTS" | jq '.telemetry.player_level // 0' 2>/dev/null)
TOTAL_FIRES=$(echo "$RESULTS" | jq '.telemetry.total_fires // 0' 2>/dev/null)
LEVEL_UPS=$(echo "$RESULTS" | jq '.telemetry.level_ups // 0' 2>/dev/null)

# Count skills
SKILLS_JSON=$(echo "$RESULTS" | jq -r '.telemetry.skills_fired // {}' 2>/dev/null)
SKILL_COUNT=$(echo "$SKILLS_JSON" | jq 'length' 2>/dev/null || echo "0")

log "[Pipeline]   Run Desire:      $RUN_DESIRE ($DESIRE_RATING)"
log "[Pipeline]   Dead Time:       ${DEAD_TIME}s ($DEAD_RATING)"
log "[Pipeline]   Action Density:  $ACTION_DENSITY evt/s ($ACTION_RATING)"
log "[Pipeline]   Reward Freq:     $REWARD_FREQ /min ($REWARD_RATING)"
log "[Pipeline]   Difficulty:      $DIFF_RATING"
log "[Pipeline]   HP Floor:        $(echo "$LOWEST_HP" | awk '{printf "%.0f%%", $1 * 100}')"

# ===== STEP 3: Compute Pipeline Health Score =====
# Weighted composite: Desire(40%) + DeadTime(20%) + ActionDensity(20%) + RewardFreq(20%)
# Each sub-score normalized to 0.0-1.0

DESIRE_NORM=$(echo "$RUN_DESIRE" | awk '{v=$1; if(v<0) v=0; if(v>1) v=1; print v}')

# Dead time: 0s=1.0, 10s+=0.0 (linear decay)
DEAD_NORM=$(echo "$DEAD_TIME" | awk '{v=1.0 - $1/10.0; if(v<0) v=0; if(v>1) v=1; print v}')

# Action density: 1.0 evt/s=0.5, 2.0=1.0, 0.5=0.25 (linear)
ACTION_NORM=$(echo "$ACTION_DENSITY" | awk '{v=$1/2.0; if(v<0) v=0; if(v>1) v=1; print v}')

# Reward frequency: 20/min=0.5, 40=1.0 (linear)
REWARD_NORM=$(echo "$REWARD_FREQ" | awk '{v=$1/40.0; if(v<0) v=0; if(v>1) v=1; print v}')

HEALTH_SCORE=$(echo "$DESIRE_NORM $DEAD_NORM $ACTION_NORM $REWARD_NORM" | awk '{
    score = $1 * 0.40 + $2 * 0.20 + $3 * 0.20 + $4 * 0.20
    printf "%.2f", score
}')

HEALTH_GRADE="F"
if echo "$HEALTH_SCORE" | awk '{exit ($1 >= 0.8) ? 0 : 1}'; then
    HEALTH_GRADE="A"
elif echo "$HEALTH_SCORE" | awk '{exit ($1 >= 0.6) ? 0 : 1}'; then
    HEALTH_GRADE="B"
elif echo "$HEALTH_SCORE" | awk '{exit ($1 >= 0.4) ? 0 : 1}'; then
    HEALTH_GRADE="C"
elif echo "$HEALTH_SCORE" | awk '{exit ($1 >= 0.2) ? 0 : 1}'; then
    HEALTH_GRADE="D"
fi

log ""
log "[Pipeline] Pipeline Health: $HEALTH_SCORE ($HEALTH_GRADE)"

# ===== STEP 4: Generate Markdown Report =====
log ""
log "[Pipeline] STEP 3: Report Generation"
log "[Pipeline] ----------------------------------------"

cat > "$REPORT_FILE" << REPORT_EOF
# Pipeline Report — $(date +%Y-%m-%d\ %H:%M)

**Verdict**: $QG_VERDICT | **Health**: $HEALTH_SCORE ($HEALTH_GRADE)

## Quality Gate

| Tier | Check | Status |
|------|-------|--------|
| 1 | Stability (pass, fires, levelups) | $(echo "$QG_OUTPUT" | grep -q 'TIER1: PASS' && echo "PASS" || echo "FAIL") |
| 2 | Balance Band ($([[ "$QG_OUTPUT" == *"TIER2"* ]] && echo "$QG_OUTPUT" | grep -oP 'Balance: \K[0-9/]+' || echo "?/?")) | $(echo "$QG_OUTPUT" | grep -oP 'TIER2: \K\S+' || echo "?") |
| 3 | Regression | $(echo "$QG_OUTPUT" | grep -oP 'TIER3: \K\S+' || echo "SKIP") |

## Feel Scorecard

| Metric | Value | Rating | Weight |
|--------|-------|--------|--------|
| Run Completion Desire | $RUN_DESIRE | $DESIRE_RATING | 40% |
| Dead Time | ${DEAD_TIME}s | $DEAD_RATING | 20% |
| Action Density | $ACTION_DENSITY evt/s | $ACTION_RATING | 20% |
| Reward Frequency | $REWARD_FREQ /min | $REWARD_RATING | 20% |

## Balance Metrics

| Metric | Value |
|--------|-------|
| Difficulty | $DIFF_RATING |
| Damage Taken | $DMG_TAKEN |
| HP Floor | $(echo "$LOWEST_HP" | awk '{printf "%.0f%%", $1 * 100}') |
| Final HP | $(echo "$FINAL_HP" | awk '{printf "%.0f%%", $1 * 100}') |
| Survived | $SURVIVED |
| Fatigue | $FATIGUE |

## Telemetry

| Metric | Value |
|--------|-------|
| Player Level | $PLAYER_LEVEL |
| Level Ups | $LEVEL_UPS |
| Avg Levelup Interval | ${AVG_INTERVAL}s |
| Total Fires | $TOTAL_FIRES |
| Kill Count | $KILL_COUNT |
| Total Events | $TOTAL_EVENTS |
| Unique Skills | $SKILL_COUNT |

## Pipeline Health Breakdown

| Component | Raw | Normalized | Weighted |
|-----------|-----|------------|----------|
| Desire | $RUN_DESIRE | $DESIRE_NORM | $(echo "$DESIRE_NORM" | awk '{printf "%.3f", $1 * 0.40}') |
| Dead Time | ${DEAD_TIME}s | $DEAD_NORM | $(echo "$DEAD_NORM" | awk '{printf "%.3f", $1 * 0.20}') |
| Action Density | $ACTION_DENSITY | $ACTION_NORM | $(echo "$ACTION_NORM" | awk '{printf "%.3f", $1 * 0.20}') |
| Reward Freq | $REWARD_FREQ | $REWARD_NORM | $(echo "$REWARD_NORM" | awk '{printf "%.3f", $1 * 0.20}') |
| **Total** | | | **$HEALTH_SCORE** |

---
*Generated by Game Factory Pipeline Orchestrator v1 at $(date -Is)*
REPORT_EOF

log "[Pipeline] Report saved: $REPORT_FILE"

# ===== STEP 5: JSON Output (optional) =====
if [[ "$JSON_OUTPUT" == true ]]; then
    jq -n \
        --arg verdict "$QG_VERDICT" \
        --arg health_score "$HEALTH_SCORE" \
        --arg health_grade "$HEALTH_GRADE" \
        --arg timestamp "$(date -Is)" \
        --arg report_file "$REPORT_FILE" \
        --argjson desire "$RUN_DESIRE" \
        --argjson dead_time "$DEAD_TIME" \
        --argjson action_density "$ACTION_DENSITY" \
        --argjson reward_freq "$REWARD_FREQ" \
        --argjson damage_taken "$DMG_TAKEN" \
        --arg lowest_hp_pct "$LOWEST_HP" \
        --arg difficulty "$DIFF_RATING" \
        --argjson player_level "$PLAYER_LEVEL" \
        --argjson total_fires "$TOTAL_FIRES" \
        '{
            pipeline: "game-factory-orchestrator-v1",
            timestamp: $timestamp,
            verdict: $verdict,
            health: { score: ($health_score | tonumber), grade: $health_grade },
            feel: {
                desire: $desire,
                dead_time: $dead_time,
                action_density: $action_density,
                reward_frequency: $reward_freq
            },
            balance: {
                damage_taken: $damage_taken,
                lowest_hp_pct: ($lowest_hp_pct | tonumber),
                difficulty: $difficulty
            },
            telemetry: {
                player_level: $player_level,
                total_fires: $total_fires
            },
            report_file: $report_file
        }'
fi

# ===== Summary =====
log ""
log "[Pipeline] =========================================="
log "[Pipeline]  VERDICT: $QG_VERDICT | HEALTH: $HEALTH_SCORE ($HEALTH_GRADE)"
log "[Pipeline] =========================================="

# Exit code matches quality gate
if [[ "$QG_VERDICT" == "NO-GO" ]]; then
    exit 1
else
    exit 0
fi
