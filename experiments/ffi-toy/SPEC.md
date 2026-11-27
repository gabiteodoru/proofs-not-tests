# Spec: `categorize`

**Status: spec agreed with the user, Nov 27, 2026; not yet implemented.** Decisions T1–T6 at the bottom were all decided as recommended. Once decided, both implementations must meet this spec: the pure-Python `categorize` in `expenses.py`, and the Lean `categorizeFFI` called through `expenses_lean.py`. Background on the choices: `notes/python-lean-contract-gaps.md`.

## Context (informative, not part of the spec)

`expenses.py` reads a CSV file: the one named by its first command-line argument, or `sample.csv` if there is none. It parses the file into records with Python's `csv.reader`; a record is usually one line, but a quoted field may span several. Empty records, and records whose first field starts with `#`, are skipped. Each remaining record describes one expense: fields 1–3 are a date, a merchant name and an amount, and field 4, if present, is the declared category. (A record with fewer than three fields makes the program crash with `IndexError`; fields after the fourth are ignored. Both are outside this spec.) For each such record the program calls `categorize` with the merchant name, the declared category (`None` if the record has no field 4; the field's text, possibly empty, if it has), and the program's fixed allow-list `ALLOWED`. On accept it adds the amount to that category's total; on reject it lists the record as rejected. The spec below is about `categorize` alone, which sees only these three values and knows nothing of records, files or amounts.

## Definitions

Everything below the Context section is normative, and each term is defined before it is used.

- **Character:** a Unicode code point, an integer from `0` to `0x10FFFF`. A Python `str` may contain any of them, including the surrogates `0xD800`–`0xDFFF`; a Lean `Char` excludes the surrogates.
- **String:** a finite sequence of characters, possibly empty. Two strings are **equal** when they have the same length and the same character at each position. No Unicode normalization is applied.
- **Substring:** `t` is a substring of `s` when `t` occurs in `s` as a contiguous block. In particular, the empty string is a substring of every string, and every string is a substring of itself.
- **Printable ASCII character:** a character from `0x20` to `0x7e` inclusive: space (`0x20`), digits, letters and punctuation. A **printable ASCII string** is a string all of whose characters are printable ASCII. The empty string is one. (T1)
- **Lower(s):** `s` with each character from `A` to `Z` (`0x41`–`0x5a`) replaced by the corresponding character from `a` to `z` (`0x61`–`0x7a`), that is, its code point plus `0x20`. Every other character is unchanged.
- **Trim(s):** `s` with its longest prefix consisting only of spaces (`0x20`) removed, and then its longest suffix consisting only of spaces removed. No other character is removed.
- **Normalize(s):** `Lower(Trim(s))`.
- **Canonical string:** a string `s` with `Normalize(s) = s`. Equivalently: it contains none of `A`–`Z`, and it neither starts nor ends with a space. The empty string is canonical.
  - Fact: `Normalize(s)` is canonical for every string `s`; that is, `Normalize(Normalize(s)) = Normalize(s)` (`Normalize` is idempotent). Reason: `Trim(s)` neither starts nor ends with a space; `Lower` changes only `A`–`Z`, so it leaves the spaces where they are, and its output contains none of `A`–`Z`. By the equivalent description, `Lower(Trim(s))` is canonical.
- **Merchant rules:** this fixed sequence of six pairs (keyword, category), in this order:
  1. (`cafe`, `food`)
  2. (`restaurant`, `food`)
  3. (`airline`, `travel`)
  4. (`taxi`, `travel`)
  5. (`hotel`, `travel`)
  6. (`staples`, `office`)
- **Guess(m),** for a string `m`: the category of the first pair in the merchant rules, in the order above, whose keyword is a substring of `Lower(m)`; or `other`, if no keyword is a substring of `Lower(m)`.
  - Fact: `Guess(m)` is always one of `food`, `travel`, `office`, `other`, each of which is non-empty and canonical.

## The function

`categorize` takes three arguments:
- `merchant`;
- `declared`, which is either absent (Python `None`, Lean `none`) or a value;
- `allowed`.

Its **outcome** is exactly one of:
- **accept `c`,** for a string `c`: Python returns `c`; Lean returns `.ok c`;
- **reject,** with an error kind and a message string: Python raises an exception of that kind; Lean returns `.error message`. Kinds and messages: T5.

`categorize` must terminate on every input, without crashing or raising any other exception.

## Behaviour

**Valid input.** The arguments are valid when all of the following hold:
- V1: `merchant` is a printable ASCII string.
- V2: `declared` is absent, or a printable ASCII string.
- V3: `allowed` is a list (T2) of strings, each of which is non-empty, printable ASCII and canonical (T3). The list may be empty (T4) and may contain repeated elements. The entries are used exactly as given: `Normalize` is applied to them only to test whether they are canonical, never to change them.

Any arguments that are not valid are **invalid**.

**Chosen category.** For valid arguments, the chosen category is:
- `Normalize(declared)`, if `declared` is a string and `Normalize(declared)` is non-empty;
- `Guess(merchant)` otherwise, that is, if `declared` is absent or consists only of spaces (including the empty string).

Fact: the chosen category is non-empty and canonical. Non-empty: `Normalize(declared)` is chosen only when it is non-empty, and `Guess(merchant)` is always non-empty. Canonical: by the Facts under `Normalize` and `Guess`.

**Outcome.**
- B1: on invalid arguments, the outcome is reject. This holds whichever condition fails, including when the failing argument would not be used (for example, an invalid `merchant` alongside a non-blank `declared`).
- B2: on valid arguments, if the chosen category is equal to some element of `allowed`, the outcome is accept with the chosen category.
- B3: on valid arguments, if the chosen category is equal to no element of `allowed`, the outcome is reject. In particular, a non-blank `declared` whose normalization is not in `allowed` is rejected; the guess is not used as a fallback.

## Claims to prove in Lean

Stated, as now, for any function with the shape of `categorizeFFI`, and then applied to `categorizeFFI`. In Lean, `allowed` has type `Array String` and `declared` has type `Option String`. So the type requirements in V2 and V3 (a string, a list, absent) are met by the time Lean is called. Lean checks the rest of V1–V3. The type requirements are enforced in Python; see "Boundary" below.

- **C1, safety:** if the outcome is accept `c`, then `c` is equal to some element of `allowed`.
- **C2, invalid input is rejected:** B1, for the conditions Lean checks: if `merchant` is not printable ASCII, or `declared` is a string that is not printable ASCII, or some element of `allowed` is empty, not printable ASCII or not canonical, then the outcome is reject.
- **C3, a declared category decides:** for valid arguments where `declared` is a string and `Normalize(declared)` is non-empty, the outcome is accept `Normalize(declared)` if that string is equal to some element of `allowed`, and reject otherwise.
- **C4, otherwise the guess decides:** for valid arguments where `declared` is absent or `Normalize(declared)` is empty, the outcome is accept `Guess(merchant)` if that string is equal to some element of `allowed`, and reject otherwise.

C2, C3 and C4 together determine whether the outcome is accept or reject for every argument, and the accepted string when it is accept: this is a full functional spec, apart from the error messages. C1 follows from C2, C3 and C4 (C2 covers invalid arguments, C3 and C4 valid ones). It is stated separately because it is the security property, and it should stay readable on its own.

Note for the write-up: for a function this small, a full functional spec is close to a second implementation. Its value is that it is written independently, in terms a reader can check, and that the proof ties the code to it. For PyJWT the spec is about API properties (S1–S4), not the full behaviour; that's where spec and code differ most.

## Boundary (Python only; trusted and tested, not proven)

The Python glue in `expenses_lean.py` must enforce the parts of V1–V3 that Lean's types make true before Lean is called. Lean can't check these, because they are Python distinctions that disappear when values are converted:

- `merchant` is a `str`; `declared` is a `str` or `None`; `allowed` is a `list` (T2) whose elements are all `str`. In particular, a `str` passed as `allowed` is rejected, not searched for substrings.
- A string containing a surrogate character (e.g. `"\ud800"`) can't be converted to a Lean string, so the glue must reject it itself. A surrogate is not printable ASCII, so the outcome must be the same as for any other non-printable character (same kind, same message; T5).

Both implementations must have the same outcome on every argument, valid or not. `difftest.py` must generate invalid inputs too: a `str` or `tuple` allow-list, control characters, non-ASCII, surrogates, empty and non-canonical entries.

## Changes from the current behaviour

Deliberate breaking changes, accepted because the toy has no users (a real migration would justify, measure and document each one):

- Any non-ASCII or control character in any argument is now rejected. Example: merchant `Café Müller`.
- Tab, CR and LF around a declared category are no longer trimmed; they make the input invalid.
- An allow-list that isn't a list of `str` is rejected (today a `str` gets substring matching in Python).
- Empty and non-canonical allow-list entries are rejected. Today an entry like `""` or `Food` is accepted but can never match.

## Out of scope

- Unicode support: future work, in `notes/python-lean-contract-gaps.md`, "Character decisions are security decisions".
- The rest of the program (CSV reading, amounts, the report).

## Decisions (all decided as recommended, Nov 27, 2026)

- **T1, characters allowed in each argument.** Recommended: printable ASCII for `merchant`, `declared` and the elements of `allowed`.
  - Why: it rules out normalization collisions, control-character injection and invisible characters in one rule, and makes Python's and Lean's trimming and lowercasing agree.
  - Alternative for `merchant`: any Unicode, with ASCII-only lowercasing on both sides (today's behaviour). `merchant` only feeds `Guess`, which can only produce one of four fixed categories, so the risk is low; but `expenses.py` prints the merchant name of each rejected line, so control characters in it would allow forged output lines. One rule for all three arguments keeps the spec shorter.
- **T2, the allow-list's type.** Recommended: `list` only. Alternative: `list` or `tuple`. Both are safe; `list` only is the shortest rule. A `str` is rejected either way.
- **T3, allow-list entries must be non-empty and canonical.** Recommended: yes, and reject the call otherwise.
  - Why: an empty or non-canonical entry (`""`, `Food`, ` food`) is never equal to the chosen category, which is always non-empty and canonical (the Fact under "Chosen category"), so the entry has no effect. That is a caller mistake that would go unnoticed; rejecting the call exposes it.
  - Alternative (not chosen): accept any entry `e` and compare the chosen category with `Normalize(e)` instead of `e`, so that `Food` would match `food`. That transforms the entries as well as `declared`, which adds a second use of `Normalize` to the behaviour and to the proof, and hides the caller's mistake instead of reporting it.
- **T4, empty allow-list.** Recommended: allowed; then every outcome is reject (by B1 and B3). Consistent with the PyJWT spec, where `algorithms=[]` rejects everything (D3 in `notes/cve-2026-48523.md`).
- **T5, error kinds.** Recommended:
  - wrong Python types (T2 and the boundary rules): `TypeError`, raised in Python before Lean is called;
  - invalid characters, or empty or non-canonical entries: `CategoryError`, with a message naming the argument;
  - a category not in `allowed`: `CategoryError("category '<c>' is not allowed")`, as today. Echoing `<c>` is safe because it is printable ASCII.
  - Both implementations produce the same messages, so `difftest.py` can compare them exactly.
- **T6, which claims to prove.** Recommended: C1–C4. Minimum: C1 and C2.
