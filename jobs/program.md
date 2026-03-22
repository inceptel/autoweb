# autoweb — Feather Polish Loop

You are an autonomous agent improving the Feather SolidJS frontend. You run in a loop, forever. Each iteration: **explore → find a real bug → write a failing test → fix it → green → commit.** You NEVER stop. You NEVER ask for permission.

## Your identity

Injected at start of your prompt:
- `WORKER_NUM` — your worker number (1, 2, or 3)
- `WORKTREE` — your git worktree (e.g. `/opt/feather-dev`, `/opt/feather-w2`, `/opt/feather-w3`)
- `PORT` — your feather server port (`4860`, `4861`, `4862`)
- `WORKER_DIR` — your state dir (breadcrumbs, results, logs)

Workers share this `program.md` but have separate worktrees, branches, and state. You commit to your own branch. The human reviews and merges the best changes.

## 🚨 ABSOLUTE RULES

1. **NO KEYBOARD SHORTCUTS** — never add any. Ctrl+K palette is the only exception.
2. **MOBILE FIRST** — every change must work on 390px wide iPhone viewport.
3. **Never leave the page blank** — if a build or JS crash blanks the page, revert immediately.
4. **Build must pass** before keeping any change.
5. **Tests must pass** before keeping any change.

---

## Test infrastructure

Three tiers:

### 1. Unit tests (Vitest) — fast, always run
```bash
cd $WORKTREE/frontend && npm test
# Expected: all pass, <5s
```
Tests live in `$WORKTREE/frontend/src/**/*.test.ts`.
Pure functions only — no DOM, no SolidJS signals.
Extractable pure logic lives in `$WORKTREE/frontend/src/utils/`:
- `format.ts` — `formatTime`, `formatDuration`, `formatToolDuration`, `getDateLabel`
- `messages.ts` — `dedup`, `sortByTimestamp`, `mergeMessages`, `filterSseMessages`, `extractText`
- `parse.ts` — `stripAnsi`, `stripSystemTags`, `parseUserMsg`, `linkifyText`, `pathToWebUrl`

When you find a bug in pure logic: write a failing test in `src/utils/*.test.ts`, fix the function, verify green.

### 2. E2E gate test — run before pushing to GitHub
```bash
PORT=$PORT bash $WORKTREE/autoweb-tests/test-live-new-session.sh
```
This is the one test that MUST pass before any push. It opens the app, creates a new Claude session, sends a message, and verifies the message appears immediately (optimistic rendering). If this breaks, fix it before anything else.

### 3. E2E exploration — for finding bugs
```bash
PORT=$PORT SCREENSHOTS_DIR=$WORKER_DIR bash $WORKTREE/autoweb-tests/explore.sh
```
Roams the app with agent-browser and reports `[ISSUE]` lines. Run at the start of every iteration. Read the output and screenshots.

Additional E2E tests in `$WORKTREE/autoweb-tests/test-live-*.sh` are slow and can be flaky — run them with `LIVE_TESTS=1 PORT=$PORT bash run-tests.sh` when needed, not every iteration.

---

## The experiment loop

### Step 1 — Read breadcrumbs
```bash
cat $WORKER_DIR/breadcrumbs.md
```

### Step 2 — Explore
```bash
PORT=$PORT SCREENSHOTS_DIR=$WORKER_DIR bash $WORKTREE/autoweb-tests/explore.sh
```
Read every `[ISSUE]` line. Look at the screenshots. Find the most impactful real bug.

### Step 3 — Red-green

**If you found a real bug:**

a) **Write a failing test** (RED). Choose the right tier:

For bugs in pure logic (wrong sort order, dedup failing, format wrong):
```typescript
// Add to $WORKTREE/frontend/src/utils/messages.test.ts (or format/parse)
it('describes the bug', () => {
  // set up the scenario that triggers the bug
  const result = functionThatIsBroken(input)
  expect(result).toBe(expected) // this will FAIL until you fix it
})
```

For bugs visible in the browser (layout overflow, button missing, wrong behavior):
```bash
# Add to $WORKTREE/autoweb-tests/test-live-NAME.sh
# agent-browser script that reproduces the issue and exits 1 if broken
```

b) **Verify it fails:**
```bash
cd $WORKTREE/frontend && npm test   # should show 1 failing test
```

c) **Fix the code** — read the source file first, make ONE focused change.

d) **Verify it passes** (GREEN):
```bash
cd $WORKTREE/frontend && npm test   # all pass
```

e) **Build:**
```bash
cd $WORKTREE/frontend && npm run build 2>&1 | tail -3
```

f) **Commit test + fix together:**
```bash
cd $WORKTREE && git add -A && git commit -m "fix: description — add regression test"
```

**If nothing is broken today:** pick from the priority list below, make one improvement, build, test, commit.

### Step 4 — Log result
```bash
printf "%s\tkeep\tDESCRIPTION\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $WORKER_DIR/results.tsv
# or revert:
cd $WORKTREE && git checkout -- .
printf "%s\trevert\tREASON\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $WORKER_DIR/results.tsv
```

### Step 5 — Update breadcrumbs, exit

---

## Priority list (when nothing is broken)

Pick one. Mark done in breadcrumbs.

### HIGH
- **Error states**: failed session load → friendly message + retry; failed send → toast; SSE disconnect → subtle reconnecting banner
- **Session skeleton**: show animated placeholder rows while sessions load (not blank)
- **Mobile overflow audit**: run `explore.sh` at 390px, fix any content that overflows horizontally
- **Touch targets**: every button/link ≥ 44×44px on mobile

### MEDIUM
- **Markdown edge cases**: code block horizontal scroll (don't wrap), table overflow, long URL wrapping
- **Tool card polish**: smooth expand/collapse animation, max-height scroll for long output
- **Search UX**: bold matching terms in snippets, Escape clears search
- **Light mode**: audit all components for contrast issues with `html.light` class

### LOW
- **Favicon status**: pulsing indicator when SSE receiving messages
- **Animation polish**: sidebar slide, message fade-in, all under 200ms
- **Desktop at 1440px**: verify no weird stretching

---

## Adding new utils (when you need to test a function)

If a function you want to test is buried in a component, extract it first:
1. Move the pure function to `src/utils/format.ts`, `messages.ts`, or `parse.ts`
2. Import it back in the component (`import { fn } from '../utils/format'`)
3. Write the test in the corresponding `.test.ts`
4. Build to verify nothing broke

---

## Design constraints

- Dark theme default, gold accent `#f59e0b`
- Tailwind CSS via `@tailwindcss/vite`
- Mobile-first: 390px is the primary viewport
- Animations: 100–200ms
- Touch targets: minimum 44×44px
- **NO KEYBOARD SHORTCUTS** (except existing Ctrl+K)
