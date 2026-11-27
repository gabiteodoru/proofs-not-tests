# Same-looking functions, different contracts (Python vs Lean)

**Status: draft lesson, Nov 25, 2026.** Found during the FFI smoke test in `experiments/ffi-toy/`. To be used in the write-up's "trusted base" section.

## What happened

- I wrote a Python function `categorize` and started a Lean version of it. The Python normalizes a label with `.strip().lower()`; the obvious Lean equivalent is `.trimAscii.toString.toLower`.
- They are not equivalent:
  - **Case:** Python's `str.lower()` lowercases all of Unicode (`"ÉCLAIR".lower() == "éclair"`). Lean's `String.toLower` only maps `A`–`Z`; its docstring says so (`Init/Data/String/Modify.lean`). Lean gives `"Éclair"`.
  - **Whitespace:** Python's `str.strip()` removes all Unicode whitespace, such as U+00A0 (no-break space) and U+2003 (em space). Lean's `trimAscii` removes only space, tab, CR and LF (`Char.isWhitespace`, `Init/Data/Char/Basic.lean`).
- Concrete divergence: a declared category `"food "` is accepted by the Python (normalized to `"food"`) and rejected by the Lean (`"food "` is not on the allow-list).
- **Nobody broke a documented contract.** Both libraries do exactly what they say. The broken contract was the unwritten one: "the Lean version behaves like the Python version." My Python comment claimed the two were "kept identical" before that was checked.
- It was found by luck: I happened to evaluate `"ÉCLAIR".toLower` while checking API names.

## Why it matters for the project

- A Lean proof is about the Lean function. It says nothing about whether that function matches the Python code it models or replaces. This is the item "the Lean model is not the Python code" in the trusted base, now with a concrete example.
- The danger is that homologous functions (same name, same apparent job) carry different contracts. A human reviewer reading `.lower()` next to `.toLower` sees the same thing.
- Here the Lean side happened to fail closed (it rejects more). The opposite direction, where the Lean side accepts more, would be a security bug introduced by the translation.

### Other known gaps at the Python/Lean boundary

- **Lone surrogates (checked):** a Python `str` can contain lone surrogates (for example `"\ud800"`, or text decoded with `surrogateescape`). `"\ud800".encode("utf-8")` raises `UnicodeEncodeError: surrogates not allowed`. A Lean `Char` carries a proof of `Char.isValidCharNat`: `n < 55296 ∨ (57343 < n ∧ n < 1114112)`, which excludes U+D800–DFFF. So such a string can't reach Lean as a `String` at all, and the glue must decide what happens (reject, most likely). Not yet tested through the FFI.
- **Integers:** Python `int` is unbounded; Lean `Nat`/`Int` are unbounded too, but `UInt64` etc. wrap. Use the unbounded types, or check ranges in the glue.
- **Equality:** Python `==` on `str` and Lean `String` equality both compare code points, with no Unicode normalization. They agree, which is good news for PyJWT's `alg not in algorithms` check. Normalization (NFC vs NFD) is a gap only if one side normalizes and the other doesn't.
- **Membership, `in` (checked Nov 26):** `alg in algorithms` is exact string equality only when `algorithms` is a list. When the caller passes a `str`, Python tests for a substring: `"ES256" in "ES256K"` is true, and PyJWT `master` then accepts an ES256 token. Lean's `List.contains` / `∈` has no such case, because a Lean `List String` can't be a `String`. The type hint `Sequence[str]` admits a `str`. Details and impact: `notes/cve-2026-48523.md`, "Investigated: … RFC 8725 §3.1".
- **ASCII-only input is not enough (checked Nov 27):** on ASCII alone, Python's default `str.strip()` removes 10 characters (tab, LF, `\v`, `\f`, CR, `\x1c`–`\x1f`, space); Lean's `trimAscii` removes 4 (space, tab, CR, LF). `"\x1cfood\x0b".strip()` is `"food"` in Python; Lean keeps both control characters. Banning control characters (printable ASCII, `0x20`–`0x7e`) removes the difference: then every one of these trims does the same thing.
- **The same gap in the toy (checked Nov 27):** `expenses.categorize("x", "foo", "food travel")` returns `"foo"`, since `in` on a `str` is a substring search. The Lean path rejects it: the glue turns the string into a list of one-character strings. `difftest.py` never generates a `str` allow-list, so it never saw this.

## Is there a formal way to deal with it?

Nothing removes the gap completely, because at some point a formal object has to be connected to code or behaviour that isn't formal. The options shrink it, move it, or make it explicit.

1. **Model the Python primitives in Lean, then prove the Lean code refines the model.**
   - Write `pyLower`, `pyStrip` in Lean following Python's documented semantics, and prove `leanCategorize = pyCategorize` (or prove they agree on a stated input domain).
   - The trust moves to "the Lean model of `str.lower` is faithful to CPython." Full `str.lower` needs Unicode tables and special cases (`"İ".lower()` has two code points), so the model is large.
   - Related work: formal semantics of Python such as λπ ("Python: The Full Monty", Politz et al., OOPSLA 2013) and K-Python (Guth, 2013), and the Nagini verifier for Python (ETH Zürich). These cover the language core more than the standard library's Unicode behaviour. Check the details before citing them.
2. **Mechanical translation instead of hand translation.**
   - For Rust, Aeneas and hax translate the actual source into Lean, so the gap shrinks to "the translator is correct." There is no mature equivalent for Python. That's why our translation is by hand, and why this gap is ours to manage.
3. **Restrict the input domain and enforce it ("parse, don't validate").**
   - State in the spec that the inputs are ASCII (or whatever the domain is), and reject anything else at the boundary, before either implementation sees it. A Lean subtype such as `{s : String // s.all Char.isAscii}` makes the restriction part of the function's type.
   - On the restricted domain the two contracts can coincide, and that's provable against a small model (option 1 becomes cheap).
   - This is the most practical formal fix. It also fits security code: refuse what you don't understand.
4. **Make the Lean code the implementation.**
   - In the FFI design (Python calls the compiled Lean function), the proven code is the running code. For that function, the question "does the model match the code?" disappears.
   - What remains is a backward-compatibility question: did the migration change behaviour? That's answered by differential testing against the old Python, not by proof. AWS Cedar ties its Rust code to its Lean model the same way: differential random testing.
   - The FFI boundary itself (encoding, surrogates, error mapping) stays trusted and must be small.
5. **Differential and property-based testing aimed at the gap.**
   - Not formal, but the standard way to check the connection. Bias generators towards known gap areas: non-ASCII letters, Unicode whitespace, surrogates, empty strings, huge integers.
   - It would have found this bug on purpose instead of by luck.

## Restricting the domain is a behaviour change, and we own it

- Option 3 changes what the code does for inputs outside the restricted domain. Users may rely on that behaviour even if it was never documented (Hyrum's law). "It was unspecified" does not make the change free, and it isn't the original authors' fault.
- A migration has three honest choices:
  - **Preserve:** model Python's full behaviour in Lean (option 1). Faithful, costly, and the Python model is trusted.
  - **Change deliberately:** restrict the domain (option 3) and treat it as a breaking change: give a reason, measure whether real inputs hit it (logs, test suites), document it, and bump the version. Rejecting what you don't understand is often right for security code, but it is a decision someone signs.
  - **Fall back:** the proven Lean path handles the restricted domain, and the old Python path handles the rest. Behaviour is preserved, but the proof covers only the restricted domain, and claims must say so ("proven for ASCII inputs").
- Writing a spec forces decisions the original code made by accident (did the author mean `strip()` to remove U+00A0, or did they just reach for `strip()`?). Making that call explicitly is the "human audits the spec" step. The process must surface it, not decide it silently.

## Character decisions are security decisions (write-up material, Nov 27)

Agreed with the user: which characters a field accepts, and how they're normalized, is a decision a human makes in the spec, per field, from what the field means. Each choice decides which of these attack classes are possible:

- **Normalization collisions:** two different inputs become equal after case mapping, so a check passes for the wrong input.
  - In 2019 GitHub's password reset was attacked this way: an email with a dotless `ı` matched another user's address after case mapping (`"ı".upper()` is `"I"`). From memory (John Gracey, "Hacking GitHub with Unicode's dotless 'i'", Nov 2019); check the source before citing.
  - Checked in Python 3.12: `"K".lower()` (Kelvin sign) is `"k"`; `"ß".upper()` is `"SS"`; `"ﬁ".upper()` is `"FI"`; `"İ".lower()` is two code points.
- **Lookalikes (homoglyphs):** Cyrillic `а` vs Latin `a`. Harmless for exact comparison, dangerous wherever a human reads the value (logs, UIs).
- **Control characters:** CR/LF forges log lines; ESC sequences rewrite terminal output; NUL truncates C strings (null-byte injection).
- **Invisible and direction-changing characters:** zero-width characters, and the bidi overrides behind "Trojan Source" (CVE-2021-42574).

Two tools, and the spec names which one each field uses:
- **Narrow the domain:** e.g. printable ASCII. It removes all four classes at once and makes Python and Lean primitives agree (see the ASCII entry above). A good MVP default.
- **Match the primitives:** accept wider input (e.g. Unicode merchant names, which real data has) but use normalization that is identical on both sides, like the toy's ASCII-only lowercasing.

**Future work: non-ASCII support** (not for the toy, not for an MVP). It needs more than a Lean function:
- Lean 4.36's `Char.toLower` is ASCII-only, so Unicode case mapping means writing or importing Unicode case tables in Lean.
- It reopens the collision question, so the spec must choose a normalization (case folding, NFC/NFKC) and say why.
- "Match Python" means matching a specific Unicode version (next section).

## Dependency upgrades change contracts (Nov 27)

- Python's `str.lower()` follows the Unicode database bundled with the interpreter, and that changes with Python releases. Unicode keeps existing case pairs stable, so the change is mainly that newly assigned characters gain mappings: a code point `lower()` left alone in one Python version can be lowercased in the next.
- Checked: Python 3.12.3 (Unicode 15.0) and 3.13.11 (Unicode 15.1) have identical `lower()` on every code point (1,433 characters change, the same ones in both). Not checked: Python 3.14, which moves to Unicode 16.0, a release that added cased scripts. Verify before citing.
- A careful developer would have to review this on every upgrade. Changelogs give one line ("unicodedata updated"), and no tool maps Unicode data changes onto the calls a codebase makes. Almost nobody does this.
- **Narrowing the domain removes the review:** on printable ASCII, `lower()` gives the same result in every version.
- **Lean has the same problem, and the build catches part of it.** Removed or renamed functions break the build (`String.trim` was gone in 4.36). A change in meaning that the proof depends on makes the proof fail. A change the claim doesn't depend on goes unnoticed, which is fine for the claim and says nothing about other behaviour.

## Proposed practice for this project

- Every Python primitive used by modeled code gets its Lean counterpart checked against Python's documentation, and the difference (if any) is recorded.
- Where they differ, choose one of the three options above explicitly, record the choice and the reason, and state the resulting claim precisely.
- The differential tests include generators for the gap areas listed above.
- The write-up lists "Python/Lean contract mismatch" in the trusted base, with this example.
