# Spec: `categorize`

**Status: spec agreed with the user, Nov 27, 2026; read line by line and approved by the user, Nov 28; not yet implemented.** Decisions D1–D6 (in [`SPEC-NOTES.md`](SPEC-NOTES.md)) were all decided as recommended. Both implementations must meet this spec: the pure-Python `categorize` in `expenses.py`, and the Lean `categorizeFFI` called through `expenses_lean.py`. Background on the choices: `notes/python-lean-contract-gaps.md`.

## Context (informative, not part of the spec)

`expenses.py` reads a CSV file: the one named by its first command-line argument, or `sample.csv` if there is none. It parses the file into records with Python's `csv.reader`; a record is usually one line, but a quoted field may span several. Empty records, and records whose first field starts with `#`, are skipped. Each remaining record describes one expense: fields 1–3 are a date, a merchant name and an amount, and field 4, if present, is the declared category. (A record with fewer than three fields makes the program crash with `IndexError`; fields after the fourth are ignored. Both are outside this spec.) For each such record the program calls `categorize` with the merchant name, the declared category (`None` if the record has no field 4; the field's text, possibly empty, if it has), and the program's fixed allow-list `ALLOWED`. On accept it adds the amount to that category's total; on reject it lists the record as rejected. The spec below is about `categorize` alone, which sees only these three values and knows nothing of records, files or amounts.

## Labels (informative, not part of the spec)

Some statements below carry a label, a letter and a number, so that other parts of the text can refer to them. The letter says what kind of statement it is:
- **V1–V3, validity conditions** (section "Behaviour", paragraph "Valid input"): the conditions the arguments must meet to be valid.
- **B1–B3, behaviour rules** (section "Behaviour", paragraph "Outcome"): what the outcome must be, for invalid arguments (B1) and for valid ones (B2, B3). Both implementations must follow them.
- **C1–C4, claims** (section "Claims to prove in Lean"): statements to be proved in Lean about the Lean implementation. C2–C4 restate B1–B3 for the parts Lean can check; C1 is the critical claim, explained after the claims.
- **D1–D6, decisions** (in a separate file, [`SPEC-NOTES.md`](SPEC-NOTES.md), which is not part of the spec and not audited): the choices made in writing this spec, each with its reason and the alternatives not chosen. A label in parentheses such as "([D2](SPEC-NOTES.md#d2))" next to a rule points to the reason for that rule. The rule itself is always stated in full where the label appears, so `SPEC-NOTES.md` need not be read.
- **PyJWT-D3 and PyJWT-S1–S4** are labels from a sibling project, the PyJWT spec in `notes/cve-2026-48523.md` (D: its decisions; S: its spec statements). A label from another project always carries that project's name as a prefix; unprefixed labels are this spec's own. They appear here only in informative remarks comparing the two specs.

## Definitions

Everything from here on is normative, and each term is defined before it is used.

- **Character:** a Unicode code point, an integer from `0` to `0x10FFFF`. A Python `str` may contain any of them, including the surrogates `0xD800`–`0xDFFF`; a Lean `Char` excludes the surrogates.
- **String:** a finite sequence of characters, possibly empty. Two strings are **equal** when they have the same length and the same character at each position. No Unicode normalization is applied.
- **Substring:** `t` is a substring of `s` when `t` occurs in `s` as a contiguous block. In particular, the empty string is a substring of every string, and every string is a substring of itself.
- **Printable ASCII character:** a character from `0x20` to `0x7e` inclusive: space (`0x20`), digits, letters and punctuation. A **printable ASCII string** is a string all of whose characters are printable ASCII. The empty string is one.
- **Lower(s):** `s` with each character from `A` to `Z` (`0x41`–`0x5a`) replaced by the corresponding character from `a` to `z` (`0x61`–`0x7a`), that is, its code point plus `0x20`. Every other character is unchanged.
- **Trim(s):** `s` with its longest prefix consisting only of spaces (`0x20`) removed, and then its longest suffix consisting only of spaces removed. No other character is removed.
- **Normalize(s):** `Lower(Trim(s))`.
- **Canonical string:** a string `s` with `Normalize(s) = s`. Equivalently: it contains none of `A`–`Z`, and it neither starts nor ends with a space. The empty string is canonical (V3 excludes it separately).
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
- **reject,** with an error kind and a message string: Python raises an exception of that kind; Lean returns `.error message`. Which kind and which message: "Error kinds and messages", under "Behaviour".

`categorize` must terminate on every input, without crashing or raising any other exception.

## Behaviour

**Valid input.** The arguments are valid when all of the following hold ([D1](SPEC-NOTES.md#d1)):
- V1: `merchant` is a printable ASCII string.
- V2: `declared` is absent, or a printable ASCII string.
- V3: `allowed` is a list ([D2](SPEC-NOTES.md#d2)) of strings, each of which is non-empty, printable ASCII and canonical ([D3](SPEC-NOTES.md#d3)). The list may be empty ([D4](SPEC-NOTES.md#d4)) and may contain repeated elements. The entries are used exactly as given: `Normalize` is applied to them only to test whether they are canonical, never to change them.

Any arguments that are not valid are **invalid**.

**Chosen category.** For valid arguments, the chosen category is:
- `Normalize(declared)`, if `declared` is a string and `Normalize(declared)` is non-empty;
- `Guess(merchant)` otherwise, that is, if `declared` is absent or consists only of spaces (including the empty string).

Fact: the chosen category is non-empty and canonical. Non-empty: `Normalize(declared)` is chosen only when it is non-empty, and `Guess(merchant)` is always non-empty. Canonical: by the Facts under `Normalize` and `Guess`.

**Outcome.**
- B1: on invalid arguments, the outcome is reject. This holds whichever condition fails, including when the failing argument would not be used (for example, an invalid `merchant` alongside a non-blank `declared`).
- B2: on valid arguments, if the chosen category is equal to some element of `allowed`, the outcome is accept with the chosen category.
- B3: on valid arguments, if the chosen category is equal to no element of `allowed`, the outcome is reject. In particular, a non-blank `declared` whose normalization is not in `allowed` is rejected; the guess is not used as a fallback.

**Error kinds and messages** ([D5](SPEC-NOTES.md#d5)). When the outcome is reject, its kind and message are:
- if some argument does not have its Python type (`merchant` a `str`; `declared` a `str` or `None`; `allowed` a `list` whose elements are all `str`): kind `TypeError`, raised in Python before Lean is called;
- otherwise, if the arguments are invalid: kind `CategoryError`, with a message that names an argument that breaks one of V1–V3;
- otherwise (the arguments are valid, and the chosen category, call it `c`, is equal to no element of `allowed`): kind `CategoryError`, with the message `category '<c>' is not allowed`, where `<c>` stands for `c`.

Where this does not give a message's text exactly, the text is not specified, except that both implementations must produce the same message for the same arguments.

## Claims to prove in Lean

Stated, as now, for any function with the shape of `categorizeFFI`, and then applied to `categorizeFFI`. In Lean, `allowed` has type `Array String` and `declared` has type `Option String`. So the type requirements in V2 and V3 (a string, a list, absent) are met by the time Lean is called. Lean checks the rest of V1–V3. The type requirements are enforced in Python; see "Boundary" below.

- **C1, critical claim:** if the outcome is accept `c`, then `c` is equal to some element of `allowed`.
- **C2, invalid input is rejected:** B1, for the conditions Lean checks: if `merchant` is not printable ASCII, or `declared` is a string that is not printable ASCII, or some element of `allowed` is empty, not printable ASCII or not canonical, then the outcome is reject.
- **C3, a declared category decides:** for valid arguments where `declared` is a string and `Normalize(declared)` is non-empty, the outcome is accept `Normalize(declared)` if that string is equal to some element of `allowed`, and reject otherwise.
- **C4, otherwise the guess decides:** for valid arguments where `declared` is absent or `Normalize(declared)` is empty, the outcome is accept `Guess(merchant)` if that string is equal to some element of `allowed`, and reject otherwise.

Fact: C2, C3 and C4 together determine the outcome on every argument that Lean can receive, apart from the error message. That is, two functions that both satisfy them either both accept the same string or both reject. Reason: if the arguments are invalid, C2 says both reject. (For arguments of Lean's types, every condition in V1–V3 is one that Lean checks, so C2 covers all invalid arguments.) If they are valid, exactly one of C3 and C4 applies, since their conditions are complementary: `declared` is either a string whose normalization is non-empty (C3), or absent or a string whose normalization is empty (C4). The claim that applies fixes the outcome: accept one named string if it is equal to some element of `allowed`, reject otherwise. So C2–C4 are a full functional spec of the Lean implementation, apart from the error message.

Fact: every function that satisfies C2, C3 and C4 also satisfies C1. Reason: suppose the outcome is accept `c`. Accept and reject are different outcomes, so by C2 the arguments are valid. For valid arguments, exactly one of C3 and C4 applies: C3 when `declared` is a string and `Normalize(declared)` is non-empty, C4 when `declared` is absent or `Normalize(declared)` is empty. Each of them gives accept only with a string that is equal to some element of `allowed`, and reject otherwise. So `c` is equal to some element of `allowed`.

C1 is still stated and proved on its own, because it is the critical claim: an accept with a category that is not in `allowed` is the outcome an attacker would want. It uses only the terms "outcome", "accept" and `allowed`, and none of the Definitions section or of "valid", so a reader can check it in one line, and a mistake in C2–C4 or in the definitions they use cannot weaken it. Why critical claims are kept separate: `verified-auth-benchmark-handoff.md`, section 6, "Critical properties get their own short claim".

**Non-vacuity.** A claim of the form "for every input with property P, …" says nothing if no input has property P. So the following are also to be proved in Lean, about the spec alone. Each says that one case of a claim can be reached:
- for C2: some arguments are invalid;
- for C3, accept and reject: some valid arguments have `declared` a string with `Normalize(declared)` non-empty, and in `allowed`; and some such arguments have it not in `allowed`;
- for C4, accept and reject: some valid arguments have `declared` absent or `Normalize(declared)` empty, and `Guess(merchant)` in `allowed`; and some such arguments have it not in `allowed`.

C1 needs no such statement: its only assumption is about the outcome. Each statement is proved by one example (a "witness"), which proves it completely.

**What the claims do not cover.** C1–C4 are about the value that the Lean implementation returns. They say nothing about the following, which are covered, if at all, by other means:
- the error kind and message text ("Error kinds and messages"): compared between the implementations by `difftest.py`;
- the Python type rules and surrogates: section "Boundary" (read by a human, and tested);
- the conversion of values between Python and Lean, in the glue `expenses_lean.py` and the C shim `c/toy_shim.c`: read by a human as part of the audit;
- the Python implementation, `categorize` in `expenses.py`: compared with the Lean one by `difftest.py`;
- the requirement under "The function" that `categorize` terminates without crashing, as far as it concerns the running program (time, memory, and crashes in the glue or the shim): not covered by any proof.

And no claim can cover whether this spec says what was intended: that is what the audit of the spec is for (`verified-auth-benchmark-handoff.md`, section 6, "The guarantee is conditional on the spec").

## Boundary (Python only; trusted and tested, not proven)

The Python glue in `expenses_lean.py` must enforce the parts of V1–V3 that Lean's types make true before Lean is called. Lean can't check these, because they are Python distinctions that disappear when values are converted:

- `merchant` is a `str`; `declared` is a `str` or `None`; `allowed` is a `list` ([D2](SPEC-NOTES.md#d2)) whose elements are all `str`. In particular, a `str` passed as `allowed` is rejected, not searched for substrings.
- A string containing a surrogate character (e.g. `"\ud800"`) can't be converted to a Lean string, so the glue must reject it itself. A surrogate is not printable ASCII, so the outcome must be the same as for any other non-printable character (same kind, same message; see "Error kinds and messages").

Who checks this, and how: no proof covers it. A human reads the glue's checks as part of the audit (decided Nov 28), so `expenses_lean.py` is in `audit.sh`'s list of audited files; and `difftest.py` tests them, with wrong-type and surrogate inputs (next paragraph).

Both implementations must have the same outcome on every argument, valid or not. `difftest.py` must generate invalid inputs too: a `str` or `tuple` allow-list, control characters, non-ASCII, surrogates, empty and non-canonical entries.
