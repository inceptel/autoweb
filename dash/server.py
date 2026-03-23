#!/usr/bin/env python3
"""Autoweb dashboard server — reads TSV files live on each request."""

import json, os, time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

HOME = Path.home()


def claude_project_dir(harness_dir: Path) -> Path:
    """Map a harness working dir to ~/.claude/projects/<slug>."""
    slug = str(harness_dir).replace("/", "-")
    return HOME / ".claude" / "projects" / slug


def latest_session_msg(harness_dir: Path) -> str:
    """Return the last assistant text from the most recent Claude session, or ''."""
    try:
        proj = claude_project_dir(harness_dir)
        if not proj.is_dir():
            return ""
        files = sorted(proj.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)
        if not files:
            return ""
        lines = files[0].read_text(errors="replace").splitlines()
        for line in reversed(lines):
            try:
                d = json.loads(line)
                msg = d.get("message", {})
                if msg.get("role") == "assistant":
                    for block in msg.get("content", []):
                        if isinstance(block, dict) and block.get("type") == "text":
                            text = block["text"].strip()
                            if text:
                                return text
            except Exception:
                pass
    except Exception:
        pass
    return ""

def discover_feather_workers():
    workers = [("w1", HOME / "autoweb")]
    for d in sorted(HOME.glob("autoweb-w*")):
        label = d.name.replace("autoweb-", "")
        workers.append((label, d))
    return workers

FEATHER_WORKERS = discover_feather_workers()

# Other instances: any ~/autoweb-X dir that isn't a feather worker
OTHER_SLUGS_SKIP = {"w2", "w3"}


def parse_tsv(path, worker_label=None):
    """Parse a results.tsv, return (keeps, reverts, crashes, skips, recent_entries)."""
    keeps = reverts = crashes = skips = 0
    entries = []
    try:
        for line in path.read_text(errors="replace").splitlines()[1:]:
            parts = line.split("\t", 2)
            if len(parts) < 2:
                continue
            ts, status = parts[0], parts[1]
            desc = parts[2] if len(parts) > 2 else ""
            if status == "keep":     keeps   += 1
            elif status == "revert": reverts += 1
            elif status == "crash":  crashes += 1
            elif status == "skip":   skips   += 1
            e = {"ts": ts, "status": status, "desc": desc}
            if worker_label:
                e["worker"] = worker_label
            entries.append(e)
    except Exception:
        pass
    return keeps, reverts, crashes, skips, entries


def is_running(d):
    try:
        deadline = int((d / "deadline").read_text().strip())
        return deadline > time.time()
    except Exception:
        return False


def load_status():
    result = []

    # --- Feather group (w1 + w2 + w3 merged) ---
    total_keeps = total_reverts = total_crashes = total_skips = 0
    all_recent = []
    workers_running = []
    worker_currents = []
    for label, d in discover_feather_workers():
        k, r, c, s, entries = parse_tsv(d / "results.tsv", worker_label=label)
        total_keeps += k; total_reverts += r; total_crashes += c; total_skips += s
        all_recent.extend(entries)
        if is_running(d):
            workers_running.append(label)
        try:
            cur = (d / "current.txt").read_text().strip()
            if cur:
                worker_currents.append(f"[{label}] {cur}")
        except Exception:
            pass

    all_recent.sort(key=lambda e: e.get("ts", ""), reverse=True)
    # latest session msg — check each running worker, use first non-empty
    last_msg = ""
    for label, d in discover_feather_workers():
        if is_running(d):
            last_msg = latest_session_msg(d)
            if last_msg:
                break
    result.append({
        "name": "feather",
        "running": len(workers_running) > 0,
        "workers_running": workers_running,
        "keeps": total_keeps, "reverts": total_reverts,
        "crashes": total_crashes, "skips": total_skips,
        "current": "\n".join(worker_currents),
        "last_msg": last_msg,
        "recent": all_recent[:150],
    })

    # --- Other instances ---
    for p in sorted(HOME.iterdir()):
        if not p.name.startswith("autoweb-"):
            continue
        slug = p.name[len("autoweb-"):]
        if slug in OTHER_SLUGS_SKIP:
            continue
        tsv = p / "results.tsv"
        if not tsv.exists():
            continue
        k, r, c, s, entries = parse_tsv(tsv)
        entries.reverse()
        current = ""
        try:
            current = (p / "current.txt").read_text().strip()
        except Exception:
            pass
        result.append({
            "name": slug, "running": is_running(p),
            "keeps": k, "reverts": r, "crashes": c, "skips": s,
            "current": current,
            "last_msg": latest_session_msg(p) if is_running(p) else "",
            "recent": entries[:100],
        })

    result.sort(key=lambda x: (-x["running"], -x["keeps"]))
    return result


HTML = open(Path(__file__).parent / "dashboard.html", "rb").read()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass  # silence access log

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        if path in ("", "/autoweb", "/"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML)
        elif path == "/api/status":
            body = json.dumps(load_status()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8096))
    print(f"Autoweb dashboard on :{port}")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
