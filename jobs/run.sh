#!/bin/bash
# autoweb — autonomous web UI improvement loop
# Karpathy-style: each iteration is a fresh Claude invocation with one job.
# The loop is bash. Claude never knows it's in a loop.
#
# Usage:
#   ./run.sh                                    # worker 1 defaults
#   WORKER_NUM=2 WORKER_DIR=/home/user/autoweb-w2 WORKTREE=/opt/feather-w2 PORT=4861 ./run.sh
#
# Env vars (set by supervisord per-worker):
#   WORKER_NUM   — 1, 2, or 3 (default 1)
#   WORKER_DIR   — per-worker state dir (results, breadcrumbs, logs)
#   WORKTREE     — git worktree to edit  (default /opt/feather-dev)
#   PORT         — feather server port   (default 4860)
#   PROGRAM      — path to program.md    (default /home/user/autoweb/jobs/program.md)

# ── Configuration ──────────────────────────────────────────────
WORKER_NUM="${WORKER_NUM:-1}"
WORKER_DIR="${WORKER_DIR:-/home/user/autoweb}"
WORKTREE="${WORKTREE:-/opt/feather-dev}"
PORT="${PORT:-4860}"

PROGRAM="${PROGRAM:-/home/user/autoweb/jobs/program.md}"   # shared across all workers
RESULTS="${RESULTS:-$WORKER_DIR/results.tsv}"
LOGDIR="${LOGDIR:-$WORKER_DIR/logs}"
TIMEOUT="${TIMEOUT:-14400}"         # seconds per iteration (default 4h)
SLEEP_ON_CRASH="${SLEEP_ON_CRASH:-300}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-10}"

# Load local env if present (for API keys etc)
[ -f "$WORKER_DIR/.env" ] && . "$WORKER_DIR/.env"
[ -f /home/user/.env ] && . /home/user/.env

# OAuth token takes precedence over API key for Claude CLI
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && unset ANTHROPIC_API_KEY
# ───────────────────────────────────────────────────────────────

mkdir -p "$LOGDIR"

if [ ! -f "$RESULTS" ]; then
    printf "timestamp\tstatus\tdescription\n" > "$RESULTS"
fi

if [ ! -f "$PROGRAM" ]; then
    echo "[autoweb-w$WORKER_NUM] ERROR: program.md not found at $PROGRAM"
    exit 1
fi

ITERATION=0
echo "[autoweb-w$WORKER_NUM] Starting — worktree=$WORKTREE port=$PORT"
echo "[autoweb-w$WORKER_NUM] Program: $PROGRAM"
echo "[autoweb-w$WORKER_NUM] Results: $RESULTS"
echo "[autoweb-w$WORKER_NUM] Logs:    $LOGDIR"

while true; do
    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Two-way sync before each iteration:
    #   w1 (dev) merges from w2 and w3 — dev is the merger
    #   w2/w3 merge from dev — workers stay current
    # Build artifacts (index-*.js/css, index.html) are gitignored so merges are clean.
    # If a source conflict occurs, we abort and let Claude work on the current state.
    HASH_BEFORE=$(git -C "$WORKTREE" rev-parse HEAD)
    if [ "$WORKER_NUM" = "1" ]; then
        git -C "$WORKTREE" merge dev-w2 dev-w3 --no-edit 2>/dev/null \
            || git -C "$WORKTREE" merge --abort 2>/dev/null
    else
        git -C "$WORKTREE" merge dev --no-edit 2>/dev/null \
            || git -C "$WORKTREE" merge --abort 2>/dev/null
    fi
    HASH_AFTER=$(git -C "$WORKTREE" rev-parse HEAD)
    if [ "$HASH_BEFORE" != "$HASH_AFTER" ]; then
        (cd "$WORKTREE/frontend" && npm run build > /dev/null 2>&1) || true
    fi
    LOGFILE="$LOGDIR/iteration-$(printf '%04d' $ITERATION)-$(date +%s).log"

    echo "[autoweb-w$WORKER_NUM] === Iteration $ITERATION at $TIMESTAMP ==="
    KEEPS=$(tail -n +2 "$RESULTS" | grep -c "keep" || echo 0)
    LAST=$(tail -n +2 "$RESULTS" | grep "keep" | tail -1 | cut -f3 | cut -c1-80)
    echo "Running at $(date -u +'%H:%M UTC') — ${KEEPS} keeps. Last: ${LAST}" > "$WORKER_DIR/current.txt"

    START_EPOCH=$(date +%s)
    DEADLINE=$((START_EPOCH + TIMEOUT))
    echo "$DEADLINE" > "$WORKER_DIR/deadline"
    LINES_BEFORE=$(wc -l < "$RESULTS")

    PROMPT="WORKER_NUM=$WORKER_NUM WORKTREE=$WORKTREE PORT=$PORT WORKER_DIR=$WORKER_DIR. You have a hard $(( TIMEOUT / 60 ))-minute timeout. Your deadline (unix epoch) is in $WORKER_DIR/deadline — run 'echo \$(($(cat $WORKER_DIR/deadline) - \$(date +%s)))s left' to check remaining time. Read $PROGRAM for your instructions. Then read $WORKER_DIR/breadcrumbs.md to see your worker's current state. Then read $RESULTS to see what this worker has already tried. Then do exactly ONE iteration of the experiment loop. Make one improvement, verify it, log it to $RESULTS, and exit."

    echo "$PROMPT" | timeout "$TIMEOUT" claude --dangerously-skip-permissions \
        > "$LOGFILE" 2>&1

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 124 ]; then
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION timed out"
        printf "%s\tcrash\tIteration timed out after %d minutes\n" "$TIMESTAMP" "$(( TIMEOUT / 60 ))" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION failed (exit $EXIT_CODE)"
        printf "%s\tcrash\tClaude exited with code %d\n" "$TIMESTAMP" "$EXIT_CODE" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    else
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION completed"
        LINES_AFTER=$(wc -l < "$RESULTS")
        if [ "$LINES_AFTER" -le "$LINES_BEFORE" ]; then
            REASON=$(tail -3 "$LOGFILE" | tr '\n' ' ' | cut -c1-120)
            [ -z "$REASON" ] && REASON="No output from Claude"
            printf "%s\tskip\t%s\n" "$TIMESTAMP" "$REASON" >> "$RESULTS"
        fi
        # Push to GitHub as FeatherBot
        BRANCH=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)
        git -C "$WORKTREE" push origin "$BRANCH" > /dev/null 2>&1 || true
    fi

    sleep "$SLEEP_BETWEEN"
done
