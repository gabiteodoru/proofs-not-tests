"""Differential test: Python `categorize` vs the Lean one called through the FFI.

Inputs are biased towards the known Python/Lean gap areas
(notes/python-lean-contract-gaps.md): non-ASCII letters whose Python
lowercase differs, Unicode whitespace, ASCII whitespace that Python's
default strip() removes but Lean's trimAscii doesn't (\\v, \\f), NUL,
lone surrogates, and empty strings.

Usage: python3 difftest.py [iterations] [seed]
"""

from __future__ import annotations

import random
import sys

import expenses
import expenses_lean
from expenses import CategoryError

ATOMS = [
    # ordinary pieces
    "food", "FOOD", "Food", "travel", "office", "other", "cafe", "Cafe",
    "TAXI", "hotel", "Staples", "airline", "restaurant", "x", "",
    # ASCII whitespace: Lean trims these four ...
    " ", "\t", "\r", "\n",
    # ... but not these, which Python's default str.strip() would remove
    "\v", "\f",
    # Unicode whitespace
    " ", " ", "　", " ",
    # non-ASCII letters with interesting Python lowercase behaviour
    "É", "İ", "K",  # Kelvin sign: Python lower() gives ASCII "k"
    "Σ", "ẞ", "Ａ",
    # NUL and a lone surrogate
    "\x00", "\ud800",
]


def rand_str(rng: random.Random) -> str:
    return "".join(rng.choice(ATOMS) for _ in range(rng.randint(0, 4)))


def outcome(fn, merchant, declared, allowed):
    try:
        return ("ok", fn(merchant, declared, allowed))
    except CategoryError as e:
        return ("error", str(e))


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    rng = random.Random(seed)
    mismatches = 0
    surrogate_cases = 0
    for i in range(n):
        merchant = rand_str(rng)
        declared = None if rng.random() < 0.3 else rand_str(rng)
        allowed = expenses.ALLOWED + ([rand_str(rng)] if rng.random() < 0.2 else [])
        has_surrogate = any(
            "\ud800" in s for s in [merchant, declared or "", *allowed]
        )
        py = outcome(expenses.categorize, merchant, declared, allowed)
        ln = outcome(expenses_lean.categorize, merchant, declared, allowed)
        if has_surrogate:
            # Documented, deliberate difference: the Lean glue rejects text that
            # can't be UTF-8 encoded; pure Python may accept it. Count, don't fail.
            surrogate_cases += 1
            continue
        if py != ln:
            mismatches += 1
            if mismatches <= 10:
                print(f"MISMATCH #{mismatches}: {merchant!r}, {declared!r}, {allowed!r}")
                print(f"   python: {py!r}")
                print(f"   lean:   {ln!r}")
    print(f"{n} cases, seed {seed}: {mismatches} mismatches "
          f"({surrogate_cases} lone-surrogate cases skipped by design)")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
