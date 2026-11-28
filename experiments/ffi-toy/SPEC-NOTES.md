# Notes on `SPEC.md`

Informative, and not audited: material about [`SPEC.md`](SPEC.md) that is useful but not needed to judge it. Every rule is stated in full in `SPEC.md`. Names in quotes ("Boundary", "Chosen category", B1 and so on) refer to `SPEC.md`.

## Decisions

The choices made in writing `SPEC.md`, each with its reason and the alternatives not chosen. All decided as recommended, Nov 27, 2026. Labelled T1–T6 until Nov 28.

### D1

**Characters allowed in each argument.** Recommended: printable ASCII for `merchant`, `declared` and the elements of `allowed`.
- Why: it rules out normalization collisions, control-character injection and invisible characters in one rule, and makes Python's and Lean's trimming and lowercasing agree.
- Alternative for `merchant`: any Unicode, with ASCII-only lowercasing on both sides (today's behaviour). `merchant` only feeds `Guess`, which can only produce one of four fixed categories, so the risk is low; but `expenses.py` prints the merchant name of each rejected line, so control characters in it would allow forged output lines. One rule for all three arguments keeps the spec shorter.

### D2

**The allow-list's type.** Recommended: `list` only. Alternative: `list` or `tuple`. Both are safe; `list` only is the shortest rule. A `str` is rejected either way.

### D3

**Allow-list entries must be non-empty and canonical.** Recommended: yes, and reject the call otherwise.
- Why: an empty or non-canonical entry (`""`, `Food`, ` food`) is never equal to the chosen category, which is always non-empty and canonical (the Fact under "Chosen category"), so the entry has no effect. That is a caller mistake that would go unnoticed; rejecting the call exposes it.
- Alternative (not chosen): accept any entry `e` and compare the chosen category with `Normalize(e)` instead of `e`, so that `Food` would match `food`. That transforms the entries as well as `declared`, which adds a second use of `Normalize` to the behaviour and to the proof, and hides the caller's mistake instead of reporting it.

### D4

**Empty allow-list.** Recommended: allowed; then every outcome is reject (by B1 and B3). Consistent with the PyJWT spec, where `algorithms=[]` rejects everything (PyJWT-D3 in `notes/cve-2026-48523.md`).

### D5

**Error kinds and messages.** Recommended: the rules in "Error kinds and messages", under "Behaviour".
- Why `TypeError` for wrong Python types: they are Python distinctions, checked in Python before Lean is called (see "Boundary"), and `TypeError` is Python's usual kind for them.
- Why one kind, `CategoryError`, for every other reject: it is today's behaviour for a category not in `allowed`, and callers need only one kind to catch.
- The not-allowed message is today's. Echoing `<c>` is safe because it is printable ASCII.
- Both implementations produce the same messages, so `difftest.py` can compare them exactly.
- Why the claims don't cover error kinds or message text (agreed with the user, Nov 28): the kind is chosen in the Python glue, so Lean has nothing to state it about. The text could be stated in Lean, but it is low-stakes and the wording is likely to change, and each change to a frozen spec means a new audit, so it isn't worth the larger spec.

### D6

**Which claims to prove.** Recommended: C1–C4. Minimum: C1 and C2.

## Changes from the current behaviour

Deliberate breaking changes, accepted because the toy has no users (a real migration would justify, measure and document each one):

- Any non-ASCII or control character in any argument is now rejected. Example: merchant `Café Müller`.
- Tab, CR and LF around a declared category are no longer trimmed; they make the input invalid.
- An allow-list that isn't a list of `str` is rejected (today a `str` gets substring matching in Python).
- Empty and non-canonical allow-list entries are rejected. Today an entry like `""` or `Food` is accepted but can never match.

## Out of scope

- Unicode support: future work, in `notes/python-lean-contract-gaps.md`, "Character decisions are security decisions".
- The rest of the program (CSV reading, amounts, the report).

## Note for the write-up

For a function this small, a full functional spec is close to a second implementation. Its value is that it is written independently, in terms a reader can check, and that the proof ties the implementation to it. For PyJWT the spec is about API properties (PyJWT-S1–S4), not the full behaviour; that's where spec and implementation differ most.
