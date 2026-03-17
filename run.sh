#!/bin/bash
# autoweb — autonomous web UI improvement loop
# Karpathy-style: each iteration is a fresh Claude invocation with one job.
# The loop is bash. Claude never knows it's in a loop.
#
# Usage:
#   ./run.sh                    # uses defaults below
#   TARGET=/path/to/file.html ./run.sh
#   PROGRAM=/path/to/program.md ./run.sh

# ── Configuration ──────────────────────────────────────────────
DIR="$(cd "$(dirname "$0")" && pwd)"
PROGRAM="${PROGRAM:-$DIR/program.md}"
RESULTS="${RESULTS:-$DIR/results.tsv}"
LOGDIR="${LOGDIR:-$DIR/logs}"
TIMEOUT="${TIMEOUT:-1200}"          # seconds per iteration (default 20min)
SLEEP_ON_CRASH="${SLEEP_ON_CRASH:-300}"   # seconds to wait after crash
SLEEP_BETWEEN="${SLEEP_BETWEEN:-10}"      # seconds between iterations

# Load local env if present (for API keys etc)
[ -f "$DIR/.env" ] && . "$DIR/.env"
[ -f /home/user/.env ] && . /home/user/.env

# OAuth token takes precedence over API key for Claude CLI
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && unset ANTHROPIC_API_KEY
# ───────────────────────────────────────────────────────────────

mkdir -p "$LOGDIR"

if [ ! -f "$RESULTS" ]; then
    printf "timestamp\tstatus\tdescription\n" > "$RESULTS"
fi

if [ ! -f "$PROGRAM" ]; then
    echo "[autoweb] ERROR: program.md not found at $PROGRAM"
    echo "[autoweb] Copy program.md.example to program.md and configure it."
    exit 1
fi

ITERATION=0
echo "[autoweb] Starting autonomous improvement loop"
echo "[autoweb] Program: $PROGRAM"
echo "[autoweb] Results: $RESULTS"
echo "[autoweb] Logs:    $LOGDIR"

while true; do
    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    LOGFILE="$LOGDIR/iteration-$(printf '%04d' $ITERATION)-$(date +%s).log"

    echo "[autoweb] === Iteration $ITERATION at $TIMESTAMP ==="
    KEEPS=$(tail -n +2 "$RESULTS" | grep -c "keep" || echo 0)
    LAST=$(tail -n +2 "$RESULTS" | grep "keep" | tail -1 | cut -f3 | cut -c1-80)
    echo "Running at $(date -u +'%H:%M UTC') — ${KEEPS} keeps. Last: ${LAST}" > "$DIR/current.txt"

    START_EPOCH=$(date +%s)
    DEADLINE=$((START_EPOCH + TIMEOUT))
    echo "$DEADLINE" > "$DIR/deadline"
    LINES_BEFORE=$(wc -l < "$RESULTS")

    timeout "$TIMEOUT" claude --print --dangerously-skip-permissions \
        -p "You have a hard $(( TIMEOUT / 60 ))-minute timeout. Your deadline (unix epoch) is in $DIR/deadline — run 'echo \$(($(cat $DIR/deadline) - $(date +%s)))s left' to check remaining time. Read $PROGRAM for your instructions. Then read $RESULTS to see what has already been tried. Then do exactly ONE iteration of the experiment loop described in $PROGRAM. Make one improvement, verify it, log it, and exit." \
        > "$LOGFILE" 2>&1

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 124 ]; then
        echo "[autoweb] Iteration $ITERATION timed out"
        printf "%s\tcrash\tIteration timed out after %d minutes\n" "$TIMESTAMP" "$(( TIMEOUT / 60 ))" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "[autoweb] Iteration $ITERATION failed (exit $EXIT_CODE)"
        printf "%s\tcrash\tClaude exited with code %d\n" "$TIMESTAMP" "$EXIT_CODE" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    else
        echo "[autoweb] Iteration $ITERATION completed"
        LINES_AFTER=$(wc -l < "$RESULTS")
        if [ "$LINES_AFTER" -le "$LINES_BEFORE" ]; then
            REASON=$(tail -3 "$LOGFILE" | tr '\n' ' ' | cut -c1-120)
            [ -z "$REASON" ] && REASON="No output from Claude"
            printf "%s\tskip\t%s\n" "$TIMESTAMP" "$REASON" >> "$RESULTS"
        fi
    fi

    sleep "$SLEEP_BETWEEN"
done
