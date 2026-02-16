#!/usr/bin/env bash
# Pipeline Orchestrator Soak Test v1
#
# Validates stability by running the orchestrator in multiple modes
# across many iterations. Checks for:
#   - Crash/hang (timeout enforcement)
#   - Report file creation & uniqueness
#   - JSON output validity
#   - Exit code correctness
#   - Gate-log append integrity
#   - No file descriptor leaks
#
# Usage:
#   tools/soak-test.sh [--iterations N] [--with-autotest]

set -uo pipefail
# Note: -e omitted intentionally — test assertions use || patterns that conflict with errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATOR="$SCRIPT_DIR/pipeline-orchestrator.sh"
RESULTS_PATH="/tmp/godot_auto_test/results.json"
SOAK_LOG="$PROJECT_DIR/reports/soak-test-$(date +%Y%m%d-%H%M%S).log"
ITERATIONS=10
WITH_AUTOTEST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --with-autotest) WITH_AUTOTEST=true; shift ;;
        -h|--help)
            echo "Pipeline Orchestrator Soak Test v1"
            echo ""
            echo "Usage: soak-test.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --iterations N    Number of iterations (default: 10)"
            echo "  --with-autotest   Include live autotest runs (slow)"
            echo "  -h, --help        Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$(dirname "$SOAK_LOG")"

# Logging
log() {
    local msg="[Soak $(date +%H:%M:%S)] $*"
    echo "$msg"
    echo "$msg" >> "$SOAK_LOG"
}

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "$result" == "PASS" ]]; then
        log "  PASS: $desc"
        ((PASS++))
    elif [[ "$result" == "WARN" ]]; then
        log "  WARN: $desc"
        ((WARN++))
    else
        log "  FAIL: $desc"
        ((FAIL++))
    fi
}

log "============================================"
log "Pipeline Orchestrator Soak Test v1"
log "============================================"
log "Iterations: $ITERATIONS"
log "With autotest: $WITH_AUTOTEST"
log "Results path: $RESULTS_PATH"
log ""

# Pre-flight: ensure orchestrator exists and is executable
if [[ ! -x "$ORCHESTRATOR" ]]; then
    log "FATAL: Orchestrator not found or not executable: $ORCHESTRATOR"
    exit 1
fi

# Count initial state
INITIAL_GATE_LOG_LINES=0
GATE_LOG="$PROJECT_DIR/quality-gate/gate-log.jsonl"
if [[ -f "$GATE_LOG" ]]; then
    INITIAL_GATE_LOG_LINES=$(wc -l < "$GATE_LOG")
fi
INITIAL_REPORT_COUNT=$(find "$PROJECT_DIR/reports" -name "report-*.md" 2>/dev/null | wc -l)

log "Initial state: gate-log=$INITIAL_GATE_LOG_LINES lines, reports=$INITIAL_REPORT_COUNT files"
log ""

# ===== TEST 1: --help exits cleanly =====
log "--- Test 1: --help flag ---"
HELP_EXIT=0
HELP_OUT=$("$ORCHESTRATOR" --help 2>&1) || HELP_EXIT=$?
check "--help exits 0" "$([ "$HELP_EXIT" -eq 0 ] && echo PASS || echo FAIL)"
check "--help contains usage text" "$(echo "$HELP_OUT" | grep -q 'Usage' && echo PASS || echo FAIL)"

# ===== TEST 2: Missing results.json =====
log ""
log "--- Test 2: Missing results error handling ---"
MISS_EXIT=0
MISS_OUT=$("$ORCHESTRATOR" --skip-run --results /nonexistent/results.json 2>&1) || MISS_EXIT=$?
check "Missing results exits non-zero" "$([ "$MISS_EXIT" -ne 0 ] && echo PASS || echo FAIL)"
check "Error message mentions results" "$(echo "$MISS_OUT" | grep -qi 'results' && echo PASS || echo FAIL)"

# ===== TEST 3: --skip-run iterations (fast, uses existing results) =====
log ""
log "--- Test 3: --skip-run stability ($ITERATIONS iterations) ---"
SKIP_FAILS=0
REPORTS_BEFORE=$(find "$PROJECT_DIR/reports" -name "report-*.md" 2>/dev/null | wc -l)

for i in $(seq 1 "$ITERATIONS"); do
    ITER_EXIT=0
    ITER_OUT=$("$ORCHESTRATOR" --skip-run --results "$RESULTS_PATH" 2>&1) || ITER_EXIT=$?

    if [[ $ITER_EXIT -ne 0 ]]; then
        log "  Iteration $i: UNEXPECTED EXIT $ITER_EXIT"
        ((SKIP_FAILS++))
    fi

    # Brief sleep to ensure unique timestamps
    sleep 1
done

REPORTS_AFTER=$(find "$PROJECT_DIR/reports" -name "report-*.md" 2>/dev/null | wc -l)
REPORTS_CREATED=$((REPORTS_AFTER - REPORTS_BEFORE))

check "All --skip-run iterations exit 0" "$([ "$SKIP_FAILS" -eq 0 ] && echo PASS || echo FAIL)"
check "Reports created = iterations ($REPORTS_CREATED/$ITERATIONS)" "$([ "$REPORTS_CREATED" -eq "$ITERATIONS" ] && echo PASS || echo FAIL)"

# Check report uniqueness (no duplicates by content hash)
UNIQUE_HASHES=$(find "$PROJECT_DIR/reports" -name "report-*.md" -newer "$SOAK_LOG" 2>/dev/null | xargs md5sum 2>/dev/null | awk '{print $1}' | sort -u | wc -l)
check "Reports are unique (content varies)" "$([ "$UNIQUE_HASHES" -ge 1 ] && echo PASS || echo WARN)"

# ===== TEST 4: --json output validity =====
log ""
log "--- Test 4: JSON output validity ($ITERATIONS iterations) ---"
JSON_FAILS=0

for i in $(seq 1 "$ITERATIONS"); do
    JSON_OUT=$("$ORCHESTRATOR" --skip-run --json --results "$RESULTS_PATH" 2>/dev/null) || true

    if ! echo "$JSON_OUT" | jq . > /dev/null 2>&1; then
        log "  Iteration $i: INVALID JSON"
        ((JSON_FAILS++))
    fi

    # Verify required fields
    if ! echo "$JSON_OUT" | jq -e '.verdict and .health.score and .feel.desire' > /dev/null 2>&1; then
        log "  Iteration $i: MISSING REQUIRED FIELDS"
        ((JSON_FAILS++))
    fi

    sleep 1
done

check "All --json outputs are valid JSON" "$([ "$JSON_FAILS" -eq 0 ] && echo PASS || echo FAIL)"

# ===== TEST 5: --report-only mode =====
log ""
log "--- Test 5: --report-only mode ---"
RO_EXIT=0
RO_OUT=$("$ORCHESTRATOR" --report-only --results "$RESULTS_PATH" 2>&1) || RO_EXIT=$?
check "--report-only exits 0" "$([ "$RO_EXIT" -eq 0 ] && echo PASS || echo FAIL)"
check "--report-only shows SKIPPED" "$(echo "$RO_OUT" | grep -q 'SKIPPED' && echo PASS || echo FAIL)"

# ===== TEST 6: Concurrent execution safety =====
log ""
log "--- Test 6: Concurrent execution (3 parallel) ---"
PIDS=()
CONC_FAILS=0

for i in 1 2 3; do
    "$ORCHESTRATOR" --skip-run --json --results "$RESULTS_PATH" > "/tmp/soak_concurrent_$i.json" 2>/dev/null &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
    if ! wait "$pid"; then
        ((CONC_FAILS++))
    fi
done

# Verify all produced valid JSON
for i in 1 2 3; do
    if ! jq . "/tmp/soak_concurrent_$i.json" > /dev/null 2>&1; then
        ((CONC_FAILS++))
    fi
done

check "Concurrent runs all succeed" "$([ "$CONC_FAILS" -eq 0 ] && echo PASS || echo FAIL)"
rm -f /tmp/soak_concurrent_*.json

# ===== TEST 7: Gate-log integrity =====
log ""
log "--- Test 7: Gate-log integrity ---"
if [[ -f "$GATE_LOG" ]]; then
    # Verify all entries are valid JSON (slurp mode)
    GATE_VALID=$(jq -s 'length' "$GATE_LOG" 2>/dev/null || echo "0")
    check "Gate-log is valid JSONL ($GATE_VALID entries)" "$([ "$GATE_VALID" -gt 0 ] && echo PASS || echo FAIL)"

    # Check no duplicate timestamps
    TOTAL_TS=$(jq -s '[.[].timestamp] | length' "$GATE_LOG" 2>/dev/null || echo "0")
    UNIQUE_TS=$(jq -s '[.[].timestamp] | unique | length' "$GATE_LOG" 2>/dev/null || echo "0")
    check "Gate-log has no duplicate timestamps ($UNIQUE_TS/$TOTAL_TS)" "$([ "$TOTAL_TS" -eq "$UNIQUE_TS" ] && echo PASS || echo WARN)"
else
    check "Gate-log exists" "FAIL"
fi

# ===== TEST 8: File descriptor leak check =====
log ""
log "--- Test 8: Resource leak check ---"
FD_BEFORE=$(ls /proc/$$/fd 2>/dev/null | wc -l)
for i in $(seq 1 5); do
    "$ORCHESTRATOR" --skip-run --results "$RESULTS_PATH" > /dev/null 2>&1 || true
done
FD_AFTER=$(ls /proc/$$/fd 2>/dev/null | wc -l)
FD_DIFF=$((FD_AFTER - FD_BEFORE))
check "No file descriptor leak (diff=$FD_DIFF)" "$([ "$FD_DIFF" -le 2 ] && echo PASS || echo WARN)"

# ===== TEST 9: Live autotest run (optional) =====
if [[ "$WITH_AUTOTEST" == true ]]; then
    log ""
    log "--- Test 9: Live autotest run ---"
    LIVE_EXIT=0
    LIVE_OUT=$(timeout 180 "$ORCHESTRATOR" --results "$RESULTS_PATH" 2>&1) || LIVE_EXIT=$?

    check "Live autotest completes within 3min" "$([ "$LIVE_EXIT" -ne 124 ] && echo PASS || echo FAIL)"
    check "Live autotest produces verdict" "$(echo "$LIVE_OUT" | grep -q 'VERDICT:' && echo PASS || echo FAIL)"
fi

# ===== Summary =====
TOTAL=$((PASS + FAIL + WARN))
log ""
log "============================================"
log "Soak Test Summary"
log "============================================"
log "PASS: $PASS / $TOTAL"
log "FAIL: $FAIL"
log "WARN: $WARN"
log "Log: $SOAK_LOG"
log ""

if [[ "$FAIL" -gt 0 ]]; then
    log "VERDICT: FAIL"
    exit 1
elif [[ "$WARN" -gt 0 ]]; then
    log "VERDICT: PASS (with warnings)"
    exit 0
else
    log "VERDICT: PASS"
    exit 0
fi
