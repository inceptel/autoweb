#!/bin/bash
# autoweb review loop — runs every 4 hours
# Analyzes iteration logs, updates program.md with learnings
# Usage: AUTOWEB_DIR=/path/to/instance REPO=/path/to/target/repo ./review.sh
#        Or run directly from an autoweb instance directory

INSTANCE_DIR="${AUTOWEB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
REPO="${REPO:-}"  # optional: git repo to push program.md updates to
GIT_TOKEN="${GIT_TOKEN:-}"
INTERVAL="${REVIEW_INTERVAL:-14400}"  # 4 hours default

[ -f /home/user/.env ] && . /home/user/.env
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && unset ANTHROPIC_API_KEY

mkdir -p "$INSTANCE_DIR/reviews"

while true; do
    echo "[review] === Meta-review at $(date) ==="
    LOGFILE="$INSTANCE_DIR/reviews/review-$(date +%Y%m%d-%H%M).md"
    PROGRAM=$(find "$INSTANCE_DIR" "$REPO" -name "program.md" 2>/dev/null | head -1)

    timeout 600 claude --print --dangerously-skip-permissions \
        -p "You are the meta-reviewer for an autoweb autonomous improvement loop.

Read these files:
1. $INSTANCE_DIR/results.tsv — all iteration outcomes (keep/revert/crash/skip)
2. $PROGRAM — current instructions and known issues
3. Recent iteration logs: $(ls -t $INSTANCE_DIR/logs/ 2>/dev/null | head -5 | while read f; do echo "$INSTANCE_DIR/logs/$f"; done | tr '\n' ' ')

Write a review to $LOGFILE covering:
## Stats: total iterations, keeps, reverts, crashes, keep rate since last review
## Patterns: what types of changes succeed/fail, repeated attempts, ignored issues
## Recommendations: specific program.md updates

Then make surgical updates to $PROGRAM:
- Mark fixed issues complete, add newly discovered ones
- Update CURRENT FOCUS if warranted
- Add rules learned from experience at the bottom

Do NOT edit the target HTML. You are reviewer only. Exit when done." \
        > "$LOGFILE" 2>&1

    echo "[review] Done → $LOGFILE"

    # Push program.md if repo configured
    if [ -n "$REPO" ] && [ -n "$GIT_TOKEN" ] && [ -f "$PROGRAM" ]; then
        cd "$REPO"
        git add program.md
        git -c "url.https://mza9:${GIT_TOKEN}@github.com/.insteadOf=https://github.com/" \
            commit -m "autoweb: review — update program.md" 2>/dev/null && \
        git -c "url.https://mza9:${GIT_TOKEN}@github.com/.insteadOf=https://github.com/" \
            push origin main 2>/dev/null && \
        echo "[review] pushed program.md to GitHub"
    fi

    echo "[review] Sleeping ${INTERVAL}s..."
    sleep "$INTERVAL"
done
