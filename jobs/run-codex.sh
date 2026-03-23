#!/bin/bash
# autoweb — codex worker loop (w4/w5/w6)
# Same structure as run.sh but invokes codex exec instead of claude.
#
# Env vars (set by supervisord per-worker):
#   WORKER_NUM   — 4, 5, or 6
#   WORKER_DIR   — per-worker state dir
#   WORKTREE     — git worktree to edit
#   PORT         — feather server port

WORKER_NUM="${WORKER_NUM:-4}"
WORKER_DIR="${WORKER_DIR:-/home/user/autoweb-w4}"
WORKTREE="${WORKTREE:-/opt/feather-w4}"
PORT="${PORT:-4863}"

PROGRAM="${PROGRAM:-/home/user/autoweb/jobs/program.md}"
RESULTS="${RESULTS:-$WORKER_DIR/results.tsv}"
LOGDIR="${LOGDIR:-$WORKER_DIR/logs}"
TIMEOUT="${TIMEOUT:-14400}"
SLEEP_ON_CRASH="${SLEEP_ON_CRASH:-300}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-10}"
CODEX="${CODEX:-/home/user/.local/bin/codex}"

[ -f "$WORKER_DIR/.env" ] && . "$WORKER_DIR/.env"
[ -f /home/user/.env ] && . /home/user/.env

mkdir -p "$LOGDIR"

if [ ! -f "$RESULTS" ]; then
    printf "timestamp\tstatus\tdescription\n" > "$RESULTS"
fi

ITERATION=0
echo "[autoweb-w$WORKER_NUM] Starting codex worker — worktree=$WORKTREE port=$PORT"

while true; do
    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Two-way sync: w4/w5/w6 merge dev before each iteration
    HASH_BEFORE=$(git -C "$WORKTREE" rev-parse HEAD)
    git -C "$WORKTREE" merge dev --no-edit 2>/dev/null \
        || git -C "$WORKTREE" merge --abort 2>/dev/null
    HASH_AFTER=$(git -C "$WORKTREE" rev-parse HEAD)
    if [ "$HASH_BEFORE" != "$HASH_AFTER" ]; then
        (cd "$WORKTREE/frontend" && npm run build > /dev/null 2>&1) || true
    fi

    LOGFILE="$LOGDIR/iteration-$(printf '%04d' $ITERATION)-$(date +%s).log"
    echo "[autoweb-w$WORKER_NUM] === Iteration $ITERATION at $TIMESTAMP ==="

    KEEPS=$(tail -n +2 "$RESULTS" | grep -c "keep" || echo 0)
    LAST=$(tail -n +2 "$RESULTS" | grep "keep" | tail -1 | cut -f3 | cut -c1-80)
    echo "Running at $(date -u +'%H:%M UTC') — ${KEEPS} keeps. Last: ${LAST}" > "$WORKER_DIR/current.txt"

    DEADLINE=$(($(date +%s) + TIMEOUT))
    echo "$DEADLINE" > "$WORKER_DIR/deadline"
    LINES_BEFORE=$(wc -l < "$RESULTS")

    PROMPT="WORKER_NUM=$WORKER_NUM WORKTREE=$WORKTREE PORT=$PORT WORKER_DIR=$WORKER_DIR. You have a hard $(( TIMEOUT / 60 ))-minute timeout. Your deadline (unix epoch) is in $WORKER_DIR/deadline. Read $PROGRAM for your instructions. Then read $WORKER_DIR/breadcrumbs.md to see your worker's current state. Then read $RESULTS to see what this worker has already tried. Then do exactly ONE iteration of the experiment loop. Make one improvement, verify it, log it to $RESULTS, and exit."

    echo "$PROMPT" | timeout "$TIMEOUT" "$CODEX" exec \
        --dangerously-bypass-approvals-and-sandbox \
        - \
        > "$LOGFILE" 2>&1

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 124 ]; then
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION timed out"
        printf "%s\tcrash\tIteration timed out after %d minutes\n" "$TIMESTAMP" "$(( TIMEOUT / 60 ))" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION failed (exit $EXIT_CODE)"
        printf "%s\tcrash\tCodex exited with code %d\n" "$TIMESTAMP" "$EXIT_CODE" >> "$RESULTS"
        sleep "$SLEEP_ON_CRASH"
    else
        echo "[autoweb-w$WORKER_NUM] Iteration $ITERATION completed"
        LINES_AFTER=$(wc -l < "$RESULTS")
        if [ "$LINES_AFTER" -le "$LINES_BEFORE" ]; then
            REASON=$(tail -3 "$LOGFILE" | tr '\n' ' ' | cut -c1-120)
            [ -z "$REASON" ] && REASON="No output from Codex"
            printf "%s\tskip\t%s\n" "$TIMESTAMP" "$REASON" >> "$RESULTS"
        fi
        # w4/w5/w6 don't push — dev (w1) merges and pushes
    fi

    sleep "$SLEEP_BETWEEN"
done
