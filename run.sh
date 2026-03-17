#!/bin/bash
. /home/user/.env
# Use OAuth token (CLAUDE_CODE_OAUTH_TOKEN from .env) — don't set ANTHROPIC_API_KEY or it takes precedence
unset ANTHROPIC_API_KEY
# autoweb — autonomous Feather UI improvement loop
# Karpathy-style: each iteration is a fresh Claude invocation with one job.
# The loop is bash. Claude never knows it's in a loop.

LOGDIR="/home/user/autoweb/logs"
RESULTS="/home/user/autoweb/results.tsv"
PROGRAM="/home/user/autoweb/program.md"
TARGET="/opt/feather-dev/static/index.html"
DEV_URL="http://localhost:4860"
ITERATION=0

mkdir -p "$LOGDIR"

# Initialize results.tsv if needed
if [ ! -f "$RESULTS" ]; then
    printf "timestamp\tstatus\tdescription\n" > "$RESULTS"
fi

echo "[autoweb] Starting autonomous improvement loop"
echo "[autoweb] Target: $TARGET"
echo "[autoweb] Results: $RESULTS"
echo "[autoweb] Logs: $LOGDIR"

while true; do
    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    LOGFILE="$LOGDIR/iteration-$(printf '%04d' $ITERATION)-$(date +%s).log"

    echo "[autoweb] === Iteration $ITERATION at $TIMESTAMP ==="
    KEEPS_SO_FAR=$(tail -n +2 "$RESULTS" | grep -c "keep" || echo 0)
    LAST_KEEP=$(tail -n +2 "$RESULTS" | grep "keep" | tail -1 | cut -f3 | cut -c1-80)
    echo "Running at $(date -u +'%H:%M UTC') — ${KEEPS_SO_FAR} keeps total. Last: ${LAST_KEEP}" > /home/user/autoweb/current.txt

    # Run Claude with the program.md as context
    # --dangerously-skip-permissions: no human approval needed
    # --print: output to stdout (no interactive mode)
    # No max-turns limit — the 20-minute timeout is the safety net
    # Write a deadline file so Claude can check how much time it has left
    START_EPOCH=$(date +%s)
    DEADLINE_EPOCH=$((START_EPOCH + 1200))
    echo "$DEADLINE_EPOCH" > /home/user/autoweb/deadline
    LINES_BEFORE=$(wc -l < "$RESULTS")
    timeout 1200 claude --print --dangerously-skip-permissions \
        -p "You have a hard 20-minute timeout. Your deadline (unix epoch) is in /home/user/autoweb/deadline — run 'echo \$(($(cat /home/user/autoweb/deadline) - $(date +%s)))s left' to check remaining time. Budget your time wisely: don't start large refactors if you're running low. Read /home/user/autoweb/program.md for your instructions. Then read /home/user/autoweb/results.tsv to see what has already been tried. Then do exactly ONE iteration of the experiment loop described in program.md. Make one improvement, verify it, log it, and exit." \
        > "$LOGFILE" 2>&1

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 124 ]; then
        echo "[autoweb] Iteration $ITERATION timed out (20min limit)"
        printf "%s\tcrash\tIteration timed out after 20 minutes\n" "$TIMESTAMP" >> "$RESULTS"
        # Restore backup if it exists
        [ -f "${TARGET}.bak" ] && cp "${TARGET}.bak" "$TARGET"
        sleep 300
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "[autoweb] Iteration $ITERATION failed with exit code $EXIT_CODE — sleeping 5min"
        printf "%s\tcrash\tClaude exited with code %d\n" "$TIMESTAMP" "$EXIT_CODE" >> "$RESULTS"
        [ -f "${TARGET}.bak" ] && cp "${TARGET}.bak" "$TARGET"
        sleep 300
    else
        echo "[autoweb] Iteration $ITERATION completed"
        # Check if Claude logged anything to results.tsv this iteration
        # Compare line count before vs after (timestamp check was wrong — Claude uses date at end, not start)
        LINES_AFTER=$(wc -l < "$RESULTS")
        if [ "$LINES_AFTER" -le "$LINES_BEFORE" ]; then
            # Extract a reason from the log if possible
            SKIP_REASON=$(grep -oP '(?<=skip: ).*|(?:no .+? found|nothing to improve|already (fixed|done|correct)|no issues|looks good|no bugs|no improvements).*' "$LOGFILE" | head -1 | cut -c1-120)
            [ -z "$SKIP_REASON" ] && SKIP_REASON=$(tail -3 "$LOGFILE" | tr '\n' ' ' | cut -c1-120)
            [ -z "$SKIP_REASON" ] && SKIP_REASON="No output from Claude"
            printf "%s\tskip\t%s\n" "$TIMESTAMP" "$SKIP_REASON" >> "$RESULTS"
        fi
    fi

    # Add no-cache headers via meta tags if not present (forces iOS to fetch fresh)
    if ! grep -q "autoweb-nocache" "$TARGET"; then
        sed -i 's|<head>|<head>\n<!-- autoweb-nocache --><meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"><meta http-equiv="Pragma" content="no-cache"><meta http-equiv="Expires" content="0">|' "$TARGET"
    fi

    # Stamp the build version into the HTML so the user knows they're current
    # Injects/updates a meta tag and a tiny visible indicator
    BUILD_TS=$(date -u +"%Y-%m-%d %H:%M UTC")
    ITER_COUNT=$(tail -n +2 "$RESULTS" | grep -c "keep" || echo 0)
    sed -i "s|<!--autoweb-version:.*-->|<!--autoweb-version: $BUILD_TS iter=$ITERATION keeps=$ITER_COUNT-->|" "$TARGET"
    # If the marker doesn't exist yet, inject it after <head>
    if ! grep -q "autoweb-version:" "$TARGET"; then
        sed -i "s|<head>|<head>\n<!--autoweb-version: $BUILD_TS iter=$ITERATION keeps=$ITER_COUNT-->|" "$TARGET"
    fi

    # Brief pause between iterations
    sleep 10
done
