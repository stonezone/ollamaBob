#!/usr/bin/env python3
"""
Investigation A — num_ctx ceiling on M1/32GB.

For each (model, num_ctx) combo, measure:
  - first-token latency (via ollama's reported total_duration / eval_duration)
  - wall-clock request time
  - RSS of the ollama runner process right after the request completes
  - whether the request completed cleanly

Pass criteria (per V2 plan):
  - 16K on gemma4:e4b completes within 4s first-token latency, RSS < 22GB.

Results: phase0/invA_results.jsonl (one JSON object per trial)
         phase0/invA_summary.txt
"""

import json
import subprocess
import time
import urllib.request
import urllib.error
from pathlib import Path

HERE = Path(__file__).parent
RESULTS_PATH = HERE / "invA_results.jsonl"
SUMMARY_PATH = HERE / "invA_summary.txt"

OLLAMA_URL = "http://localhost:11434/api/chat"
MODELS = ["gemma4:e4b", "qwen3:14b"]
CTX_SIZES = [8192, 12288, 16384, 24576, 32768]

# A ~6000-word fixture so num_ctx actually matters (not just empty-prompt latency).
# Using a deterministic phrase repeated avoids any topical drift.
FIXTURE_FILLER = (
    "Consider the following inventory of directory entries that Bob might need "
    "to reason about when answering the question at the end: "
    + ("one two three four five six seven eight nine ten " * 500)
)
FIXTURE_QUESTION = " Now, in a single short sentence, estimate how many distinct words appeared in the list above."
FIXTURE = FIXTURE_FILLER + FIXTURE_QUESTION


def now_ms() -> int:
    return int(time.time() * 1000)


def ollama_post(body: dict, timeout: int = 180) -> dict:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="ignore")
        return {"error": f"http {e.code}: {body[:400]}"}
    except Exception as e:
        return {"error": str(e)}


def runner_rss_kb() -> int:
    """Return the RSS (KB) of the largest 'ollama runner' process, 0 if none."""
    try:
        out = subprocess.check_output(
            ["pgrep", "-f", "ollama runner"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
    except subprocess.CalledProcessError:
        return 0
    pids = [p for p in out.split("\n") if p]
    if not pids:
        return 0
    try:
        ps = subprocess.check_output(
            ["ps", "-o", "rss=", "-p", ",".join(pids)],
            stderr=subprocess.DEVNULL,
        ).decode().strip().split("\n")
    except subprocess.CalledProcessError:
        return 0
    return max(int(line.strip()) for line in ps if line.strip().isdigit())


def unload(model: str) -> None:
    ollama_post(
        {
            "model": model,
            "stream": False,
            "keep_alive": 0,
            "messages": [{"role": "user", "content": "ok"}],
        },
        timeout=30,
    )
    time.sleep(2)


def warm(model: str, num_ctx: int) -> None:
    """Warm the model at this context size so first-token measurement isn't load-time."""
    ollama_post(
        {
            "model": model,
            "stream": False,
            "keep_alive": "5m",
            "messages": [{"role": "user", "content": "reply with the single word ready"}],
            "options": {"num_ctx": num_ctx, "temperature": 0, "num_predict": 4},
        },
        timeout=120,
    )


def trial(model: str, num_ctx: int) -> dict:
    rss_before = runner_rss_kb()
    t0 = now_ms()
    resp = ollama_post(
        {
            "model": model,
            "stream": False,
            "keep_alive": "5m",
            "messages": [{"role": "user", "content": FIXTURE}],
            "options": {"num_ctx": num_ctx, "temperature": 0, "num_predict": 64},
        },
        timeout=180,
    )
    wall_ms = now_ms() - t0
    rss_after = runner_rss_kb()

    result = {
        "model": model,
        "num_ctx": num_ctx,
        "wall_ms": wall_ms,
        "rss_before_kb": rss_before,
        "rss_after_kb": rss_after,
        "rss_after_gb": round(rss_after / 1024 / 1024, 2),
        "ok": False,
        "total_duration_ms": None,
        "load_duration_ms": None,
        "prompt_eval_duration_ms": None,
        "eval_duration_ms": None,
        "eval_count": None,
        "error": None,
    }

    if "error" in resp:
        result["error"] = resp["error"]
        return result

    result["total_duration_ms"] = (resp.get("total_duration") or 0) // 1_000_000
    result["load_duration_ms"] = (resp.get("load_duration") or 0) // 1_000_000
    result["prompt_eval_duration_ms"] = (resp.get("prompt_eval_duration") or 0) // 1_000_000
    result["eval_duration_ms"] = (resp.get("eval_duration") or 0) // 1_000_000
    result["eval_count"] = resp.get("eval_count")
    result["ok"] = bool(resp.get("done"))
    return result


def passes(model: str, num_ctx: int, r: dict) -> bool:
    """
    Pass criteria for the V2 plan gate:
      - request completed ok
      - RSS < 22 GB
      - "first-token latency" proxy: total_duration_ms - eval_duration_ms < 4000
        (this is prompt eval + load; we warmed the model so load_duration
        should already be ~0 on the measured trial)
    """
    if not r["ok"]:
        return False
    if r["rss_after_gb"] >= 22.0:
        return False
    ttft = (r["total_duration_ms"] or 0) - (r["eval_duration_ms"] or 0)
    return ttft < 4000


def main():
    RESULTS_PATH.write_text("")
    rows = []

    print("Investigation A — num_ctx ceiling")
    print(f"Results: {RESULTS_PATH}")
    print()

    for model in MODELS:
        print(f"=== {model} ===")
        unload(model)
        for ctx in CTX_SIZES:
            print(f"  ctx={ctx:<6} warming…", end="", flush=True)
            warm(model, ctx)
            print(" trial…", end="", flush=True)
            r = trial(model, ctx)
            with RESULTS_PATH.open("a") as f:
                f.write(json.dumps(r) + "\n")
            rows.append(r)
            if r["ok"]:
                ttft = (r["total_duration_ms"] or 0) - (r["eval_duration_ms"] or 0)
                verdict = "PASS" if passes(model, ctx, r) else "FAIL"
                print(
                    f" {verdict}  wall={r['wall_ms']}ms "
                    f"total={r['total_duration_ms']}ms "
                    f"eval={r['eval_duration_ms']}ms "
                    f"ttft≈{ttft}ms "
                    f"rss={r['rss_after_gb']}GB"
                )
            else:
                print(f" ERROR  {r['error'] or 'unknown'}")
            time.sleep(1)
        unload(model)
        time.sleep(3)

    # Summary
    lines = ["Investigation A — num_ctx ceiling", ""]
    lines.append(f"{'model':<14} {'ctx':>6} {'wall_ms':>8} {'total_ms':>9} {'eval_ms':>8} {'ttft_ms':>8} {'rss_gb':>7} {'pass':>5}")
    for r in rows:
        ttft = (r["total_duration_ms"] or 0) - (r["eval_duration_ms"] or 0) if r["ok"] else -1
        ok_mark = "YES" if (r["ok"] and passes(r["model"], r["num_ctx"], r)) else "no"
        lines.append(
            f"{r['model']:<14} {r['num_ctx']:>6} "
            f"{r['wall_ms']:>8} "
            f"{r['total_duration_ms'] or 0:>9} "
            f"{r['eval_duration_ms'] or 0:>8} "
            f"{ttft:>8} "
            f"{r['rss_after_gb']:>7} "
            f"{ok_mark:>5}"
        )

    gate_ok = any(
        r["model"] == "gemma4:e4b" and r["num_ctx"] == 16384 and passes(r["model"], r["num_ctx"], r)
        for r in rows
    )
    lines.append("")
    lines.append(f"GATE (16K on gemma4:e4b, ttft<4s, rss<22GB): {'PASS' if gate_ok else 'FAIL'}")

    SUMMARY_PATH.write_text("\n".join(lines) + "\n")
    print()
    print(SUMMARY_PATH.read_text())


if __name__ == "__main__":
    main()
