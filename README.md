# autoweb

Autonomous UI improvement agent. Points at any web target and self-improves it forever.

## What it does

autoweb runs in a loop. Each iteration it:
1. Screenshots your web target with a real browser
2. Asks Claude to identify one improvement
3. Makes the change
4. Verifies it with another screenshot
5. Keeps or reverts based on the result
6. Logs everything to `results.tsv`

128 keeps, 1 revert on Feather so far. ~99% acceptance rate.

## How to use it

### Point at any target

```bash
# Clone
git clone https://github.com/inceptel/autoweb
cd autoweb

# Configure your target
cp program.md.example program.md
# Edit program.md: set your target URL, file path, and focus area

# Run
./run.sh
```

### What you need

- `claude` CLI (`npm install -g @anthropic-ai/claude-code`)
- `agent-browser` for screenshot verification
- A web target (HTML file, running server, anything with a URL)

## Files

| File | Purpose |
|------|---------|
| `run.sh` | Main loop harness |
| `program.md` | Instructions for Claude — target, focus, known issues |
| `results.tsv` | Log of every iteration (keep/revert/crash) |
| `tests/` | Test suite run after each change |

## program.md

This is the brain. It tells autoweb:
- What URL to screenshot
- What file(s) to edit
- What to focus on (mobile, performance, bugs, general)
- Known issues to fix
- Rules learned from experience

See `program.md.example` for a template.

## Instances

You can run multiple autoweb instances simultaneously on different targets:

```bash
# Feather UI
/home/user/autoweb/run.sh

# Trading dashboard
/home/user/autoweb-trading/run.sh
```

## Powered by

- [Claude Code](https://github.com/anthropics/claude-code) — the agent
- [Feather](https://github.com/inceptel/feather) — the first target

---

Built by [Inceptel](https://inceptel.com)
