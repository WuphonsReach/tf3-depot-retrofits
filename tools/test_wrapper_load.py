#!/usr/bin/env python3
"""Synthetic tests of how other mods can load the depot wrapper (the TRM: Industry Emissions fix, docs/compatibility.md).

Turns the mod's .tl files into Lua with `tl gen` in a temporary folder, then runs tools/wrapper_load_test.lua with lua5.1
against them and the mod's content folder. Needs `tl` and `lua5.1` on PATH; the game's type definitions are not needed.

    python3 tools/test_wrapper_load.py
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT = ROOT / "depot_retrofits_1" / "content"
SOURCES = ["levels.tl", "construction.script.tl", "mod.script.tl", "retrofits.script.tl"]


def main() -> int:
    for tool in ("tl", "lua5.1"):
        if shutil.which(tool) is None:
            print(f"FAIL  {tool} not found on PATH")
            return 1
    with tempfile.TemporaryDirectory() as tmp:
        for name in SOURCES:
            out = pathlib.Path(tmp) / (name[: -len(".tl")] + ".lua")
            done = subprocess.run(["tl", "gen", str(CONTENT / name), "-o", str(out)], capture_output=True, text=True)
            if done.returncode != 0:
                print(f"FAIL  tl gen {name}\n{done.stdout}{done.stderr}")
                return 1
        test = ROOT / "tools" / "wrapper_load_test.lua"
        return subprocess.run(["lua5.1", str(test), tmp, str(CONTENT)]).returncode


if __name__ == "__main__":
    sys.exit(main())
