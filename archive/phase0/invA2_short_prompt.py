#!/usr/bin/env python3
"""
Investigation A supplementary — short-prompt baseline TTFT at each num_ctx.

The main invA script used a 5K-token fixture to stress the models, but that
masked the real question: does raising num_ctx add any per-turn overhead when
the prompt is TYPICAL (say 200 tokens)?

This run uses a short "what's 2+2?" prompt and measures pure baseline latency
at each ctx size. If raising num_ctx from 8K to 32K is "free" at idle, then
flipping the default up is safe.
"""

import json
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
RESULTS = HERE / "invA2_results.jsonl"
SUMMARY = HERE / "invA2_summary.txt"

MODELS = ["gemma4:e4b", "qwen3:14b"]
CTX_SIZES = [8192, 16384, 32768]
SHORT_PROMPT = "In one word, what is 2+2?"


def post(body, timeout=120):
    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def unload(model):
    try:
        post({"model": model, "stream": False, "keep_alive": 0,
              "messages": [{"role": "user", "content": "ok"}]}, timeout=30)
    except Exception:
        pass
    time.sleep(2)


def warm(model, ctx):
    post({
        "model": model, "stream": False, "keep_alive": "5m",
        "messages": [{"role": "user", "content": "hi"}],
        "options": {"num_ctx": ctx, "num_predict": 4},
    }, timeout=120)


def trial(model, ctx):
    t0 = time.time()
    r = post({
        "model": model, "stream": False, "keep_alive": "5m",
        "messages": [{"role": "user", "content": SHORT_PROMPT}],
        "options": {"num_ctx": ctx, "temperature": 0, "num_predict": 8},
    })
    wall = int((time.time() - t0) * 1000)
    return {
        "model": model,
        "num_ctx": ctx,
        "wall_ms": wall,
        "total_ms": (r.get("total_duration") or 0) // 1_000_000,
        "load_ms": (r.get("load_duration") or 0) // 1_000_000,
        "prompt_eval_ms": (r.get("prompt_eval_duration") or 0) // 1_000_000,
        "eval_ms": (r.get("eval_duration") or 0) // 1_000_000,
        "ok": bool(r.get("done")),
    }


def main():
    RESULTS.write_text("")
    rows = []
    print("Investigation A2 — short-prompt baseline TTFT")
    print()
    for model in MODELS:
        print(f"=== {model} ===")
        unload(model)
        for ctx in CTX_SIZES:
            print(f"  ctx={ctx:<5} warm…", end="", flush=True)
            warm(model, ctx)
            print(" trial…", end="", flush=True)
            r = trial(model, ctx)
            with RESULTS.open("a") as f:
                f.write(json.dumps(r) + "\n")
            rows.append(r)
            ttft = (r["total_ms"] or 0) - (r["eval_ms"] or 0)
            print(f" wall={r['wall_ms']}ms total={r['total_ms']}ms prompt_eval={r['prompt_eval_ms']}ms eval={r['eval_ms']}ms ttft≈{ttft}ms")
            time.sleep(1)
        unload(model)

    lines = ["Investigation A2 — short-prompt baseline TTFT", ""]
    lines.append(f"{'model':<14} {'ctx':>6} {'wall':>7} {'total':>7} {'prompt_eval':>12} {'eval':>6} {'ttft':>7}")
    for r in rows:
        ttft = (r["total_ms"] or 0) - (r["eval_ms"] or 0)
        lines.append(f"{r['model']:<14} {r['num_ctx']:>6} {r['wall_ms']:>7} {r['total_ms']:>7} {r['prompt_eval_ms']:>12} {r['eval_ms']:>6} {ttft:>7}")
    SUMMARY.write_text("\n".join(lines) + "\n")
    print()
    print(SUMMARY.read_text())


if __name__ == "__main__":
    main()
