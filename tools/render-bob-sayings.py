#!/usr/bin/env python3
"""
Render Bob's sayings as MP3 clips via the ElevenLabs API.

Usage:
    python3 tools/render-bob-sayings.py           # render only new / changed
    python3 tools/render-bob-sayings.py --force   # re-render everything

Reads:  tools/bob-sayings.json
        .env  (ELEVENLABS_API_KEY, OLLAMABOB_VOICE_ID)

Writes: OllamaBob/OllamaBob/Resources/BobSayings/<category>-<hash>.mp3
        OllamaBob/OllamaBob/Resources/BobSayings/manifest.json
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "tools" / "bob-sayings.json"
ASSETS_DIR = ROOT / "OllamaBob" / "OllamaBob" / "Resources" / "BobSayings"
MANIFEST_PATH = ASSETS_DIR / "manifest.json"
ENV_PATH = ROOT / ".env"


def read_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def phrase_hash(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:10]


def render(text: str, voice_id: str, voice_cfg: dict, api_key: str, output_format: str) -> bytes:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format={output_format}"
    body = json.dumps({
        "text": text,
        "model_id": voice_cfg["model"],
        "voice_settings": {
            "stability": voice_cfg["stability"],
            "similarity_boost": voice_cfg["similarity_boost"],
            "speed": voice_cfg["speed"],
            "style": 0.0,
            "use_speaker_boost": True,
        },
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def main() -> int:
    force = "--force" in sys.argv

    env = read_env(ENV_PATH)
    api_key = os.environ.get("ELEVENLABS_API_KEY") or env.get("ELEVENLABS_API_KEY", "")
    voice_id = os.environ.get("OLLAMABOB_VOICE_ID") or env.get("OLLAMABOB_VOICE_ID", "")
    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY missing (env or .env)")
        return 1
    if not voice_id:
        print("ERROR: OLLAMABOB_VOICE_ID missing (env or .env)")
        return 1

    cfg = json.loads(CONFIG_PATH.read_text())
    voice_cfg = cfg["voice"]
    output_format = cfg.get("output_format", "mp3_44100_128")
    categories: dict[str, list[str]] = cfg["categories"]

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    manifest: dict = {"voice_id": voice_id, "entries": []}
    if MANIFEST_PATH.exists() and not force:
        try:
            manifest = json.loads(MANIFEST_PATH.read_text())
        except Exception:
            manifest = {"voice_id": voice_id, "entries": []}
    manifest["voice_id"] = voice_id

    existing = {(e["category"], e["hash"]): e for e in manifest.get("entries", [])}
    new_entries: list[dict] = []
    rendered = 0
    skipped = 0
    failures = 0

    for category, phrases in categories.items():
        for text in phrases:
            h = phrase_hash(text)
            filename = f"{category}-{h}.mp3"
            out_path = ASSETS_DIR / filename
            key = (category, h)

            if not force and key in existing and out_path.exists():
                new_entries.append(existing[key])
                skipped += 1
                continue

            preview = text if len(text) <= 60 else text[:57] + "..."
            print(f"  [{category}/{filename}] {preview}", end=" ... ", flush=True)
            try:
                audio = render(text, voice_id, voice_cfg, api_key, output_format)
                out_path.write_bytes(audio)
                new_entries.append({
                    "category": category,
                    "hash": h,
                    "text": text,
                    "file": filename,
                    "bytes": len(audio),
                })
                rendered += 1
                print(f"OK ({len(audio)} bytes)")
                time.sleep(0.25)
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", errors="replace")
                print(f"HTTP {e.code}: {body[:200]}")
                failures += 1
            except Exception as e:
                print(f"FAIL: {e}")
                failures += 1

    manifest["entries"] = new_entries
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")

    print("\n" + "─" * 40)
    print(f"Rendered: {rendered}")
    print(f"Skipped:  {skipped}")
    if failures:
        print(f"Failures: {failures}")
    print(f"Manifest: {MANIFEST_PATH}")
    return 0 if failures == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
