#!/usr/bin/env python3
"""Parse a task.toml and emit a compact JSON object describing the build target.

Output fields: task, toml, name, engine, commit_hash, placeholder.

Engine detection is resilient to schema changes: it looks, in priority order, for
an explicit `engine` scalar, then `tech-stack-tags`, then a unified `tags` list.
This way the workflow keeps working whether the repo keeps faceted tag lists or
collapses them into one.
"""
import json
import os
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    print(json.dumps({"error": "tomllib unavailable (need Python 3.11+)"}),
          file=sys.stderr)
    sys.exit(2)

# canonical engine -> tokens that identify it (lowercased, exact-match)
ENGINE_MAP = [
    ("godot", {"godot"}),
    ("love", {"love", "love2d"}),
    ("raylib", {"raylib"}),
]

HASH_RE = re.compile(r"^[0-9a-fA-F]{7,40}$")


def _tokens(value):
    """Normalize a scalar or list into a set of lowercased string tokens."""
    if value is None:
        return set()
    if isinstance(value, str):
        value = [value]
    return {str(v).strip().lower() for v in value}


def detect_engine(data, game):
    # 1) explicit scalar wins (either top-level or under [game])
    explicit = _tokens(data.get("engine")) | _tokens(game.get("engine"))
    # 2) tech-stack-tags, 3) unified tags list
    candidates = [
        explicit,
        _tokens(game.get("tech-stack-tags")) | _tokens(data.get("tech-stack-tags")),
        _tokens(game.get("tags")) | _tokens(data.get("tags")),
    ]
    for toks in candidates:
        for canon, keys in ENGINE_MAP:
            if toks & keys:
                return canon
    return "unknown"


def main():
    if len(sys.argv) != 2:
        print("usage: read_task_toml.py <path/to/task.toml>", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = tomllib.load(f)

    game = data.get("game") or {}
    task = os.path.basename(os.path.dirname(os.path.abspath(path)))
    name = str(data.get("name") or task)
    engine = detect_engine(data, game)
    commit = str(game.get("commit-hash") or data.get("commit-hash") or "").strip()
    placeholder = (not commit) or commit == "<hash>" or not HASH_RE.match(commit)

    print(json.dumps({
        "task": task,
        "toml": path,
        "name": name,
        "engine": engine,
        "commit_hash": commit,
        "placeholder": placeholder,
    }))


if __name__ == "__main__":
    main()
