"""Toy expense report: the all-Python original.

Reads a CSV of expenses (date,merchant,amount[,category]) and prints totals
per category. Categories must come from an allow-list.

The function `categorize` is the one we move to Lean in `expenses_lean.py`.
It has the same shape as PyJWT's algorithm choice: an untrusted label
(the declared category), a policy (the allow-list), and a decision that
may reject.
"""

from __future__ import annotations

import csv
import sys
from collections import defaultdict
from typing import Callable, Iterable, Optional, Sequence

ALLOWED = ["food", "travel", "office", "other"]

# Keyword -> category, used when a row declares no category.
# First match wins. Kept identical to the table in Lean.
MERCHANT_RULES = [
    ("cafe", "food"),
    ("restaurant", "food"),
    ("airline", "travel"),
    ("taxi", "travel"),
    ("hotel", "travel"),
    ("staples", "office"),
]


class CategoryError(ValueError):
    pass


# Normalization is ASCII-only, on purpose, so that it matches Lean's
# String.toLower / String.trimAscii exactly. Python's own str.lower() and
# str.strip() are Unicode-aware; using them made the Python and Lean versions
# disagree (see notes/python-lean-contract-gaps.md). This was a deliberate
# behaviour change to the original version of this file.
_ASCII_WS = " \t\r\n"  # Lean's Char.isWhitespace. Note: not \v or \f.
_UPPER_TO_LOWER = str.maketrans(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"
)


def ascii_lower(s: str) -> str:
    return s.translate(_UPPER_TO_LOWER)


def ascii_trim(s: str) -> str:
    return s.strip(_ASCII_WS)


def categorize(
    merchant: str, declared: Optional[str], allowed: Sequence[str]
) -> str:
    """Pick the category for one expense row.

    - A declared category is normalized (ASCII-trimmed, ASCII-lowercased)
      and used, unless it is empty after trimming.
    - Otherwise the first merchant rule whose keyword appears in the
      ASCII-lowercased merchant name decides; if none matches, "other".
    - The result must be in `allowed`, else CategoryError.
    """
    if declared is not None and ascii_trim(declared) != "":
        category = ascii_lower(ascii_trim(declared))
    else:
        m = ascii_lower(merchant)
        category = "other"
        for keyword, cat in MERCHANT_RULES:
            if keyword in m:
                category = cat
                break
    if category not in allowed:
        raise CategoryError(f"category '{category}' is not allowed")
    return category


def parse_amount(s: str) -> int:
    """Parse '12.34' into cents (1234). Rejects negatives and >2 decimals."""
    s = s.strip()
    if s.count(".") > 1 or not s.replace(".", "", 1).isdigit():
        raise ValueError(f"bad amount {s!r}")
    whole, _, frac = s.partition(".")
    if len(frac) > 2:
        raise ValueError(f"bad amount {s!r}")
    return int(whole or "0") * 100 + int(frac.ljust(2, "0") or "0")


def read_rows(lines: Iterable[str]):
    for row in csv.reader(lines):
        if not row or row[0].startswith("#"):
            continue
        date, merchant, amount = row[0], row[1], row[2]
        declared = row[3] if len(row) > 3 else None
        yield date, merchant, amount, declared


def summarize(
    lines: Iterable[str],
    allowed: Sequence[str] = ALLOWED,
    categorize_fn: Callable[[str, Optional[str], Sequence[str]], str] = categorize,
):
    totals: dict[str, int] = defaultdict(int)
    rejected: list[tuple[str, str]] = []
    for date, merchant, amount, declared in read_rows(lines):
        try:
            cat = categorize_fn(merchant, declared, allowed)
        except CategoryError as e:
            rejected.append((f"{date} {merchant}", str(e)))
            continue
        totals[cat] += parse_amount(amount)
    return dict(totals), rejected


def format_report(totals: dict[str, int], rejected) -> str:
    out = []
    for cat in sorted(totals):
        c = totals[cat]
        out.append(f"{cat:<8} {c // 100:>6}.{c % 100:02d}")
    out.append(f"{'TOTAL':<8} {sum(totals.values()) // 100:>6}.{sum(totals.values()) % 100:02d}")
    for what, why in rejected:
        out.append(f"rejected: {what}: {why}")
    return "\n".join(out)


def main(argv: list[str], categorize_fn=categorize) -> int:
    path = argv[1] if len(argv) > 1 else "sample.csv"
    with open(path, newline="") as f:
        totals, rejected = summarize(f, categorize_fn=categorize_fn)
    print(format_report(totals, rejected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
