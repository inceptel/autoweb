# autoweb

An autonomous UI improvement agent. Point it at any website and it improves itself forever.

```
screenshot → pick one thing → change it → verify → keep or revert → repeat
```

No human in the loop. Every iteration is a fresh Claude invocation. The loop is bash.

---

## How it works

autoweb runs `claude` in a tight loop. Each iteration:

1. Screenshots the live URL with a real browser
2. Reads `program.md` for instructions and focus
3. Picks **one** improvement (bug fix, UX, visual polish, new feature)
4. Makes the change to the target file
5. Runs your test suite
6. Takes another screenshot to verify
7. Keeps or reverts based on the result
8. Logs to `results.tsv` and exits

The harness restarts it immediately. Repeat forever.

A separate **review loop** (`review.sh`) runs every 4 hours, reads the iteration logs, and updates `program.md` with learnings — so the agent gets smarter over time.

---

## Quick start

```bash
git clone https://github.com/inceptel/autoweb
cd myproject

# 1. Copy the template
cp ../autoweb/program.md.example program.md

# 2. Edit program.md: set your target URL and file path

# 3. Run
PROGRAM=./program.md ../autoweb/run.sh
```

**Requirements:** `claude` CLI (`npm i -g @anthropic-ai/claude-code`) + `agent-browser`

---

## Files

| File | Purpose |
|------|---------|
| `run.sh` | Main loop — configurable via env vars |
| `review.sh` | Meta-review loop — updates program.md every 4h |
| `program.md.example` | Template — copy and configure for your project |
| `dashboard/index.html` | Results viewer — point at any `results.tsv` |

---

## Configuration

`run.sh` is controlled by env vars:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROGRAM` | `./program.md` | Path to your program.md |
| `RESULTS` | `./results.tsv` | Where to log results |
| `LOGDIR` | `./logs/` | Per-iteration Claude output |
| `TIMEOUT` | `1200` | Seconds per iteration (20 min) |
| `SLEEP_ON_CRASH` | `300` | Wait after crash before retry |

---

## Dashboard

Open `dashboard/index.html` in a browser and pass a `results.tsv` URL:

```
dashboard/index.html?url=https://raw.githubusercontent.com/YOU/REPO/main/results.tsv
```

Live example (NBA dashboard):
```
dashboard/index.html?url=https://raw.githubusercontent.com/inceptel/nba/main/results.tsv
```

---

## Live example

**[inceptel/nba](https://github.com/inceptel/nba)** — an NBA scores dashboard that autoweb has been improving autonomously. Every commit is from the agent.

- Dashboard: https://allan.feather-cloud.dev/public/nba/
- Results: https://raw.githubusercontent.com/inceptel/nba/main/results.tsv

---

## program.md

This is the brain. It tells the agent:

- What URL to screenshot
- What file to edit
- What to focus on right now
- Known issues (priority ordered)
- Rules learned from past iterations
- How to run tests

See `program.md.example` for a full template.

---

## Review loop

```bash
AUTOWEB_DIR=./myinstance REPO=./myrepo ./review.sh
```

Reads iteration logs every 4 hours, extracts patterns (what keeps failing, what keeps succeeding), and surgically updates `program.md`. If `REPO` is a git repo, it commits and pushes the updated `program.md` automatically.

---

## Results log

`results.tsv` has three columns:

```
timestamp    status    description
2026-03-17T21:43:07Z    keep    Add ESPN team logos with CDN fallback
2026-03-17T21:45:21Z    keep    Add yesterday/tomorrow date navigation
2026-03-17T21:53:34Z    keep    Add Standings tab with conference tables
```

Status values: `keep` · `revert` · `crash` · `skip`

---

Built by [Inceptel](https://inceptel.com)
