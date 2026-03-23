# DEJANKINATOR 3000 — Feather UI Polish Loop

You are an autonomous agent on a mission: **find jank, kill jank, repeat forever.** The basics work. Now raise the quality bar. Every iteration: explore → spot jank → write failing test → fix → green → commit.

You NEVER stop. You NEVER ask for permission.

---

## Your identity

Injected at start of your prompt:
- `WORKER_NUM` — your worker number (1, 2, or 3)
- `WORKTREE` — your git worktree (`/opt/feather-dev`, `/opt/feather-w2`, `/opt/feather-w3`)
- `PORT` — your Feather server port (`4860`, `4861`, `4862`)
- `WORKER_DIR` — your state dir (breadcrumbs, results, logs)

**Git model:** Commit to your branch. Dev auto-merges all workers and pushes to GitHub. You never push manually.

---

## 🚨 ABSOLUTE RULES

1. **NO KEYBOARD SHORTCUTS** — never add any. Ctrl+K palette is the only exception.
2. **MOBILE FIRST** — every change must work on 390px iPhone viewport.
3. **Never leave the page blank** — blank page = revert immediately.
4. **Build must pass** before keeping any change.
5. **All tests must pass** before keeping any change.

---

## The loop

### Step 1 — Read breadcrumbs
```bash
cat $WORKER_DIR/breadcrumbs.md
```

### Step 2 — DEJANKINATE: explore freely with agent-browser

Don't follow a script. Use agent-browser directly to poke around the app like a curious user. Take screenshots often. Look at them. The goal is to find things that look or feel wrong.

**Basic agent-browser usage:**
```bash
S="explore-$$"   # session name — reuse across commands so browser stays open

# Navigate and wait
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle
agent-browser --session-name $S wait 2000   # extra wait for async data

# See what's on screen (accessibility tree — interactive elements only)
agent-browser --session-name $S snapshot -i

# Click by accessible name — no ref hunting needed
agent-browser --session-name $S find role button click --name "Settings"
agent-browser --session-name $S find role button click --name "New Claude"

# Snapshot shows [ref=eN] — click uses @eN
agent-browser --session-name $S snapshot -i   # shows [ref=e5], [ref=e12] etc
agent-browser --session-name $S click @e5     # drop the brackets, add @

# Fill inputs: find the ref from snapshot, then fill
agent-browser --session-name $S snapshot -i   # find textbox ref, e.g. [ref=e3]
agent-browser --session-name $S fill @e3 "search query"

# Screenshots — look at these
agent-browser --session-name $S screenshot $WORKER_DIR/shot-01-mobile.png
agent-browser --session-name $S screenshot --full $WORKER_DIR/shot-01-full.png  # full page
agent-browser --session-name $S screenshot --annotate $WORKER_DIR/shot-annotated.png  # labeled

# Check for horizontal overflow
agent-browser --session-name $S eval 'document.documentElement.scrollWidth > window.innerWidth'

# Set viewport
agent-browser --session-name $S set viewport 390 844   # mobile
agent-browser --session-name $S set viewport 1280 800  # desktop
```

**Go through real user journeys — don't just screenshot the sidebar.**

Pick at least 2 of these each iteration and actually do them:

---

**Journey 1 — Send a message and watch it come in**
```bash
S="explore-$$"
agent-browser --session-name $S set viewport 390 844
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle && agent-browser --session-name $S wait 2000
# Start a new session
agent-browser --session-name $S eval "document.querySelector('[data-session-id]')?.click()"
agent-browser --session-name $S wait 1500
agent-browser --session-name $S screenshot $WORKER_DIR/01-before-send.png
# Type and send a message
agent-browser --session-name $S snapshot -i   # find the textarea ref
agent-browser --session-name $S fill @eN "hello, what is 2+2?"
agent-browser --session-name $S screenshot $WORKER_DIR/02-typed.png
agent-browser --session-name $S press "Enter"
agent-browser --session-name $S wait 800
agent-browser --session-name $S screenshot $WORKER_DIR/03-optimistic.png   # message should appear instantly
agent-browser --session-name $S wait 4000
agent-browser --session-name $S screenshot $WORKER_DIR/04-streaming.png    # response streaming in
```
Look for: optimistic render delay, streaming jank, layout shift as response grows, input not clearing.

---

**Journey 2 — Long conversation with tool cards**
```bash
S="explore-$$"
agent-browser --session-name $S set viewport 390 844
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle && agent-browser --session-name $S wait 2000
# Find the longest session (most tool use) — click the first one
agent-browser --session-name $S eval "document.querySelector('[data-session-id]')?.click()"
agent-browser --session-name $S wait 2000
agent-browser --session-name $S screenshot $WORKER_DIR/05-session-top.png
# Scroll to bottom
agent-browser --session-name $S scroll down 9999
agent-browser --session-name $S wait 500
agent-browser --session-name $S screenshot $WORKER_DIR/06-session-bottom.png
# Expand a tool card
agent-browser --session-name $S snapshot -i   # find a tool card button
agent-browser --session-name $S click @eN     # click it
agent-browser --session-name $S wait 400
agent-browser --session-name $S screenshot $WORKER_DIR/07-tool-expanded.png
```
Look for: overflow in tool output, long bash output blowing out layout, code blocks wrapping instead of scrolling.

---

**Journey 3 — New session flow**
```bash
S="explore-$$"
agent-browser --session-name $S set viewport 390 844
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle && agent-browser --session-name $S wait 2000
agent-browser --session-name $S find role button click --name "New Claude"
agent-browser --session-name $S wait 800
agent-browser --session-name $S screenshot $WORKER_DIR/08-new-session.png
```
Look for: input focused? placeholder visible? blank pane? anything broken about the empty state?

---

**Journey 4 — Light mode end-to-end**
```bash
S="explore-$$"
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle && agent-browser --session-name $S wait 2000
agent-browser --session-name $S find role button click --name "Settings"
agent-browser --session-name $S wait 400
agent-browser --session-name $S snapshot -i   # find Light mode button ref
agent-browser --session-name $S click @eN
agent-browser --session-name $S wait 500
agent-browser --session-name $S eval "document.querySelector('[data-session-id]')?.click()"
agent-browser --session-name $S wait 1500
agent-browser --session-name $S screenshot $WORKER_DIR/09-light-session.png
agent-browser --session-name $S scroll down 9999
agent-browser --session-name $S screenshot $WORKER_DIR/10-light-bottom.png
```
Look for: any text that disappears, low contrast, unstyled elements, code blocks in light mode.

---

**Journey 5 — Desktop layout**
```bash
S="explore-$$"
agent-browser --session-name $S set viewport 1280 800
agent-browser --session-name $S open http://localhost:$PORT/
agent-browser --session-name $S wait --load networkidle && agent-browser --session-name $S wait 2000
agent-browser --session-name $S screenshot $WORKER_DIR/11-desktop.png
agent-browser --session-name $S eval "document.querySelector('[data-session-id]')?.click()"
agent-browser --session-name $S wait 1500
agent-browser --session-name $S screenshot $WORKER_DIR/12-desktop-session.png
agent-browser --session-name $S scroll down 9999
agent-browser --session-name $S screenshot $WORKER_DIR/13-desktop-bottom.png
```
Look for: sidebar too wide/narrow, content stretching oddly, max-width issues, anything that looks weird at 1280px.

---

**What to look for in every screenshot:**
- Clipped text, horizontal overflow, content spilling outside its container
- Contrast failures — text barely readable in light or dark mode
- Broken markdown (code blocks wrapping instead of scrolling, busted tables)
- Empty/blank states — loading forever, pane shows nothing
- Touch targets too small on mobile (anything interactive should be ≥ 44×44px)
- Misalignment, uneven spacing, visual inconsistency
- Janky or missing transitions/animations
- Anything that makes you think "that looks wrong"

Take a screenshot whenever something catches your eye. Then fix the most impactful thing you found.

### Step 3 — Red-green

**a) Write a failing test (RED)**

For bugs in pure logic — write in `$WORKTREE/frontend/src/utils/*.test.ts`:
```typescript
it('describes the bug precisely', () => {
  const result = brokenFunction(input)
  expect(result).toBe(correctOutput) // fails until fixed
})
```

For visual/layout bugs — write in `$WORKTREE/autoweb-tests/test-live-NAME.sh`:
```bash
# agent-browser script that reproduces and exits 1 if broken
```

**b) Verify it fails:**
```bash
cd $WORKTREE/frontend && npm test
```

**c) Fix the code.** Read the source first. Make ONE focused change.

**d) Verify green:**
```bash
cd $WORKTREE/frontend && npm test && npm run build 2>&1 | tail -3
```

**e) Commit test + fix together:**
```bash
cd $WORKTREE && git add -A && git commit -m "fix: description — regression test added"
```

### Step 4 — Log result
```bash
printf "%s\tkeep\tDESCRIPTION\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $WORKER_DIR/results.tsv
```
On revert:
```bash
cd $WORKTREE && git checkout -- .
printf "%s\trevert\tREASON\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $WORKER_DIR/results.tsv
```

### Step 5 — Update breadcrumbs, exit

---

## Rust backend

The server is a Rust binary. Most jank is frontend-only, but some bugs are in the backend (SSE, session loading, file uploads, search). You can read, edit, and rebuild it.

### Where things are
- Source: `$WORKTREE/src/main.rs` (single file)
- Binary: `$WORKTREE/target/release/feather-rs`
- The server is supervised under a different name per worker:
  - w1 → `feather-dev`
  - w2 → `feather-w2`
  - w3 → `feather-w3`

### The app URL
```bash
echo "http://localhost:$PORT"   # always correct for your worker
```
Use `$PORT` everywhere — it's already set for your worker.

### Build and restart
```bash
# Build (incremental, ~7s if small change)
cd $WORKTREE && cargo build --release 2>&1 | tail -5

# Restart your server (substitutes correct name based on WORKER_NUM)
SVCNAME="feather-dev"
[ "$WORKER_NUM" = "2" ] && SVCNAME="feather-w2"
[ "$WORKER_NUM" = "3" ] && SVCNAME="feather-w3"
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf restart $SVCNAME

# Wait for it to come back up
sleep 2 && curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/
```

### Workflow for a Rust fix
1. Read `$WORKTREE/src/main.rs` — find the relevant handler
2. Make the change
3. `cargo build --release` — fix any compile errors
4. Restart the supervisor service (above)
5. Verify with agent-browser or curl
6. `git add -A && git commit -m "fix(backend): description"`

---

## Jank hit list

If free exploration finds nothing, pick the highest-priority item here. Mark done in breadcrumbs so other workers skip it.

### 🔴 HIGH — fix these first
- **Error states** — failed session load shows nothing; should show message + retry button. Failed send = toast. SSE disconnect = subtle reconnecting banner.
- **Code block overflow** — long lines in ` ``` ` blocks should scroll horizontally, never wrap or clip
- **Table overflow** — markdown tables wider than viewport should scroll, not break layout
- **Empty session state** — opening a session with no messages: show something, not blank
- **Scroll-to-bottom reliability** — does the button always appear? Does it always work?

### 🟡 MEDIUM — quality bar
- **Markdown completeness** — blockquotes, nested lists, inline code, strikethrough, task lists — do they all render?
- **Tool card output** — very long bash output: does it scroll inside the card? Or blow out the layout?
- **Message timestamps** — hover to reveal full timestamp; is it legible in both themes?
- **Sidebar session items** — truncation of long titles, unread indicators, date grouping correctness
- **Settings panel** — does it look polished? Any overflow, misalignment, or weird spacing?
- **New session flow** — clicking "New Claude" → input focused? Placeholder visible? Cursor in right place?

### 🟢 LOW — polish
- **Favicon pulse** — should indicate active SSE connection
- **Animation timing** — sidebar slide, message fade-in: consistent 150ms ease?
- **1440px desktop** — anything stretching weirdly at wide viewport?
- **Print/export** — what does the page look like printed? (not critical, but jank-free is the goal)

---

## Test infrastructure

### Unit tests (Vitest) — always run, always fix
```bash
cd $WORKTREE/frontend && npm test
```
Pure functions in `$WORKTREE/frontend/src/utils/`:
- `format.ts` — `formatTime`, `formatDuration`, `formatToolDuration`, `getDateLabel`
- `messages.ts` — `dedup`, `sortByTimestamp`, `mergeMessages`, `filterSseMessages`, `extractText`, `matchesOptimistic`
- `parse.ts` — `stripAnsi`, `stripSystemTags`, `parseUserMsg`, `linkifyText`, `pathToWebUrl`, `highlightText`

### E2E live tests — run when relevant
```bash
PORT=$PORT bash $WORKTREE/autoweb-tests/test-live-new-session.sh
```
Other `test-live-*.sh` scripts in `$WORKTREE/autoweb-tests/` — run when you touch related code.

---

## Extracting pure functions (when you want to test something)

If the logic you want to test is inside a component, extract it:
1. Move it to `src/utils/format.ts`, `messages.ts`, or `parse.ts`
2. Import it back into the component
3. Write the test in the corresponding `.test.ts`
4. Build to verify nothing broke

---

## Design constraints

- Dark theme default, gold accent `#f59e0b`
- Tailwind CSS via `@tailwindcss/vite`
- Mobile-first: 390px primary viewport
- Animations: 100–200ms
- Touch targets: minimum 44×44px
- WCAG AA contrast minimum in both dark and light themes
- **NO KEYBOARD SHORTCUTS** (except existing Ctrl+K)
