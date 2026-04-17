#!/usr/bin/env python3
"""
Investigation B — shell quoting reliability on gemma4:e4b.

For each fixture prompt, we:
  1. Send it to Ollama's native /api/chat with the exact same tool definition
     Bob's ShellTool uses (flat schema, command: string).
  2. Inspect the response's message.tool_calls list.
  3. Score the outcome:
     - PASS: parsed as a tool_call to "shell" with a 'command' string arg, and
       that command string does not contain unescaped placeholder markers
       like "<...>", "[...]", or an incomplete quote.
     - FAIL_NO_TOOL: model did not call the shell tool at all.
     - FAIL_PARSE: tool_call arguments field could not be decoded as JSON or
       an object.
     - FAIL_EMPTY: shell tool called but with an empty/null command.

Pass criteria: ≥45/50 PASS on a single run.

Output: phase0/invB_results.jsonl (one line per fixture)
        phase0/invB_summary.txt   (aggregate pass/fail count per category)
"""

import json
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

HERE = Path(__file__).parent
FIXTURES_PATH = HERE / "invB_fixtures.json"
RESULTS_PATH = HERE / "invB_results.jsonl"
SUMMARY_PATH = HERE / "invB_summary.txt"

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "gemma4:e4b"

SHELL_TOOL_DEF = {
    "type": "function",
    "function": {
        "name": "shell",
        "description": "Run a shell command on macOS (BSD userland). Returns stdout/stderr.",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The complete POSIX shell command to execute."
                }
            },
            "required": ["command"]
        }
    }
}

SYSTEM_PROMPT = """You are a shell assistant on macOS. You have one tool: shell(command).
When the user asks you to run a command, IMMEDIATELY call the shell tool with the complete command.
Do not narrate. Do not say "I will run". Just emit the tool call.
Quote shell arguments correctly. Preserve special characters the user included in their request.
This is macOS (BSD userland), not Linux — use POSIX-compatible flags."""


def post_chat(prompt: str) -> dict:
    payload = {
        "model": MODEL,
        "stream": False,
        "keep_alive": "5m",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "tools": [SHELL_TOOL_DEF],
        "options": {
            "num_ctx": 8192,
            "temperature": 0,
            "num_predict": 512,
        },
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"error": f"http {e.code}: {e.read().decode(errors='ignore')}"}
    except Exception as e:
        return {"error": str(e)}


PLACEHOLDER_PATTERNS = [
    re.compile(r"<[A-Za-z_][A-Za-z0-9_ ]*>"),     # <placeholder>
    re.compile(r"\[[A-Za-z_][A-Za-z0-9_ ]*\]"),   # [placeholder]
    re.compile(r"\{[A-Z_]+\}"),                    # {VAR}
]


def looks_like_placeholder(cmd: str) -> bool:
    """Catch cases where the model emitted 'rm -rf <path>' instead of a real command."""
    for pat in PLACEHOLDER_PATTERNS:
        if pat.search(cmd):
            return True
    return False


def score_response(fixture: dict, response: dict) -> dict:
    result = {
        "id": fixture["id"],
        "category": fixture["category"],
        "prompt": fixture["prompt"],
        "status": "FAIL_UNKNOWN",
        "command": None,
        "error": None,
        "raw_message_text": None,
    }

    if "error" in response:
        result["status"] = "FAIL_HTTP"
        result["error"] = response["error"]
        return result

    msg = response.get("message", {})
    result["raw_message_text"] = msg.get("content", "")
    tool_calls = msg.get("tool_calls") or []

    if not tool_calls:
        result["status"] = "FAIL_NO_TOOL"
        return result

    # Pick the first shell call (Bob's agent loop processes them sequentially anyway)
    shell_call = None
    for tc in tool_calls:
        fn = tc.get("function", {})
        if fn.get("name") == "shell":
            shell_call = tc
            break

    if shell_call is None:
        result["status"] = "FAIL_WRONG_TOOL"
        result["error"] = f"called {[tc.get('function', {}).get('name') for tc in tool_calls]}"
        return result

    args = shell_call["function"].get("arguments")
    # Native /api/chat usually returns arguments as a dict, but sometimes as a string.
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError as e:
            result["status"] = "FAIL_PARSE"
            result["error"] = f"arguments was a string that did not parse: {e}"
            return result

    if not isinstance(args, dict):
        result["status"] = "FAIL_PARSE"
        result["error"] = f"arguments was {type(args).__name__}"
        return result

    cmd = args.get("command")
    if not isinstance(cmd, str) or not cmd.strip():
        result["status"] = "FAIL_EMPTY"
        return result

    if looks_like_placeholder(cmd):
        result["status"] = "FAIL_PLACEHOLDER"
        result["command"] = cmd
        return result

    result["status"] = "PASS"
    result["command"] = cmd
    return result


def main():
    fixtures = json.loads(FIXTURES_PATH.read_text())["fixtures"]

    RESULTS_PATH.write_text("")
    passed = 0
    total = len(fixtures)
    by_category = {}

    print(f"Investigation B: {total} fixtures against {MODEL}")
    print()

    for i, fixture in enumerate(fixtures, 1):
        print(f"[{i}/{total}] {fixture['id']:>2} {fixture['category']:<32} ", end="", flush=True)
        t0 = time.time()
        response = post_chat(fixture["prompt"])
        dt_ms = int((time.time() - t0) * 1000)

        result = score_response(fixture, response)
        result["wall_ms"] = dt_ms

        with RESULTS_PATH.open("a") as f:
            f.write(json.dumps(result) + "\n")

        cat = fixture["category"]
        if cat not in by_category:
            by_category[cat] = {"pass": 0, "fail": 0}
        if result["status"] == "PASS":
            by_category[cat]["pass"] += 1
            passed += 1
            print(f"PASS  {dt_ms:>5}ms")
        else:
            by_category[cat]["fail"] += 1
            print(f"{result['status']:<18} {dt_ms:>5}ms")
            if result.get("command"):
                print(f"           cmd: {result['command'][:120]}")
            if result.get("error"):
                print(f"           err: {result['error'][:120]}")

    print()
    print(f"=== {passed}/{total} PASS ===")
    print()
    lines = [f"Investigation B summary — {MODEL}", f"{passed}/{total} PASS", ""]
    for cat, counts in by_category.items():
        tot = counts["pass"] + counts["fail"]
        lines.append(f"  {cat:<32} {counts['pass']}/{tot}")
    SUMMARY_PATH.write_text("\n".join(lines) + "\n")
    print(SUMMARY_PATH.read_text())

    sys.exit(0 if passed >= 45 else 1)


if __name__ == "__main__":
    main()
