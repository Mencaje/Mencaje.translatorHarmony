#!/usr/bin/env python3
"""Rewrite piper-plus config.json phoneme_id_map for C++ inference.

HuggingFace tsukuyomi-chan configs may ship multi-codepoint keys (e.g. ɔɪ, œ̃, ɐ̃).
piper.cpp rejects those with: "Phonemes must be one codepoint (phoneme id map)".

Maps them to single PUA codepoints per piper-plus FIXED_PUA_MAPPING (v2).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# piper-plus src/python_run/piper/phonemize/token_mapper.py (en/fr/pt v2)
FIXED_PUA_MAPPING: dict[str, int] = {
    "ɔɪ": 0xE062,
    "œ̃": 0xE063,
    "ɐ̃": 0xE064,
}


def _codepoint_count(s: str) -> int:
    return len(s)


def update_phoneme_id_map(config: dict[str, Any], *, strict: bool = True) -> bool:
    pid_map = config.get("phoneme_id_map")
    if not isinstance(pid_map, dict):
        raise ValueError("config missing phoneme_id_map")

    new_map: dict[str, list] = {}
    changes = False
    unmapped: list[str] = []

    for phoneme, ids in pid_map.items():
        if phoneme in FIXED_PUA_MAPPING:
            pua = chr(FIXED_PUA_MAPPING[phoneme])
            new_map[pua] = ids
            changes = True
            print(f"  mapped U+{'+'.join(f'{ord(c):04X}' for c in phoneme)} -> U+{ord(pua):04X}")
        else:
            if _codepoint_count(phoneme) > 1:
                unmapped.append(phoneme)
            new_map[phoneme] = ids

    if unmapped:
        msg = (
            f"phoneme_id_map has {len(unmapped)} multi-codepoint key(s) "
            f"without PUA mapping: {unmapped!r}"
        )
        if strict:
            raise ValueError(msg)
        print(f"WARNING: {msg}", file=sys.stderr)

    config["phoneme_id_map"] = new_map
    return changes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("config", type=Path, help="path to config.json")
    ap.add_argument(
        "--no-strict",
        action="store_true",
        help="leave unknown multi-codepoint keys unchanged",
    )
    args = ap.parse_args()

    path = args.config.resolve()
    config = json.loads(path.read_text(encoding="utf-8"))
    bad_before = [k for k in config.get("phoneme_id_map", {}) if _codepoint_count(k) > 1]
    if bad_before:
        print(f"Before: {len(bad_before)} multi-codepoint key(s)")

    changed = update_phoneme_id_map(config, strict=not args.no_strict)
    bad_after = [k for k in config.get("phoneme_id_map", {}) if _codepoint_count(k) > 1]
    if bad_after:
        print(f"After: still {len(bad_after)} multi-codepoint key(s)", file=sys.stderr)
        return 1

    if changed or bad_before:
        path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {path}")
    else:
        print("No changes needed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
