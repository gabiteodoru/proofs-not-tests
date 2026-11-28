# FFI smoke test: one Python function replaced by proven, compiled Lean

**Status: experiment, done Nov 25, 2026.** A toy run-through of the plan for PyJWT: take one function out of a Python program, rewrite it in Lean, prove a property, compile it, and call it from the otherwise unchanged Python.

## What's here

- `SPEC.md`: the plain-English spec for `categorize` that both implementations must meet. Agreed Nov 27; not yet implemented.
- `expenses.py`: the all-Python original, a small expense-report CLI. It reads `sample.csv` and prints totals per category.
- The Lean project, `lean/`, split by who writes each file and who reads it (why: `notes/audit-integrity.md`):
  - **Human-audited** (read by a person):
    - `Toy/Spec.lean`: `SPEC.md`'s definitions and claims C1–C4 in Lean. Draft (Nov 27), not yet read line by line by the user.
    - `Challenge.lean`: the theorems to prove, each a claim from `Spec.lean` about `categorizeFFI`, with `sorry` as the proof. Only C1 so far; C2–C4 join when the code meets `SPEC.md`.
    - `comparator.json`: which theorems the comparator judges, and the permitted axioms (Lean's standard three).
    - `lakefile.toml`: three libraries: `Toy` (spec and code), `Challenge` and `Solution`.
  - **Frozen, not read** (fixed before proving starts; the proofs cover its correctness):
    - `Toy/Categorize.lean`: the code. `categorize` rewritten in Lean, and `categorizeFFI`, the C-callable export, which is `categorize` itself with an `Array` in place of a `List`.
  - **Written by the agent, not read:**
    - `Solution.lean`: the proofs. The only agent-written file.
- `CheckChallenge.lean`: **human-audited.** The checks `lake comparator` doesn't do. It loads the compiled challenge as data and checks:
  - each theorem in `Challenge.lean` states exactly the intended term, built from literal names (so code imported by the challenge can't change the statement through a macro or name shadowing);
  - `Categorize.lean` declares no syntax (macros, notation, parsers, elaborators);
  - `categorizeFFI` is exported as `toy_categorize`, the symbol the C shim calls;
  - nothing in `Categorize.lean` has `@[implemented_by]` or `@[extern]`, which would make the compiled code differ from the proven definition.
- `AUDITED_COMMIT`: the commit whose audited files a human read. Only the user updates it, after reading the changed files; that update is the (re-)audit.
- `audit.sh`: **human-audited.** The proof audit, in five steps; see "How to audit". Needs Linux (`bwrap`). Its comparator step took about 12 s, or 35 s with `--paranoid`, when measured on the prototype.
- `attacks.sh`: evidence, not part of the audit. Runs the whole `audit.sh` on 12 sabotaged copies and an unchanged one, and checks each verdict (see Results). Re-run it after changing a check or upgrading Lean. Takes `--paranoid` and passes it on to `audit.sh`. About 2 minutes, or 5 with `--paranoid` (measured Nov 28).
- `attacks/`: the sabotages `attacks.sh` applies. `solution-*.lean` replaces `Solution.lean`; `*.diff` patches a file.
- `c/toy_shim.c`: a plain C API over the Lean export, so Python's `ctypes` doesn't need to know about Lean objects.
- `expenses_lean.py`: the same program, with `categorize` replaced by glue that calls the Lean code.
- `difftest.py`: a differential test of Python `categorize` against the Lean one, with inputs aimed at known Python/Lean differences.
- `c/test_shim.c`: a C driver for running the shim under valgrind.
- `build.sh`: builds everything into `build/`.

`categorize` was chosen because it has the same shape as `chooseAlgorithm` in the PyJWT model: an untrusted label (the declared category), a policy (the allow-list), and a decision that may reject.

## Run it

```sh
./build.sh
python3 expenses.py          # original
python3 expenses_lean.py     # with the Lean categorize: same output
python3 difftest.py 100000 0 # differential test
valgrind --leak-check=full ./build/test_shim
./audit.sh --paranoid        # the proof audit (commit first; needs Linux, for bwrap)
./attacks.sh                 # shows the audit can fail, and where
```

## How to audit

Three parts, all on one commit. `audit.sh` refuses to run on uncommitted changes, so "passed" means it passed on exactly what you read.

1. **The claims: do they say what we want?** This is the core of the audit, and no script can do it.
   - Read `SPEC.md`, then `lean/Toy/Spec.lean`, its line-by-line translation.
   - Judge whether the claims are the properties you care about, and whether they are strong enough.
2. **The proof: are the claims really proven, about the code Python calls?** Read these, which are short:
   - `lean/Challenge.lean`: each theorem states a claim from `Spec.lean` about `categorizeFFI`.
   - `CheckChallenge.lean`: its list `expected` must state the same theorems, and its four checks are commented.
   - `lean/comparator.json`: it must name every theorem in `Challenge.lean`, and permit only `propext`, `Quot.sound` and `Classical.choice`.
   - `lean/lakefile.toml` and `audit.sh`.
   - Then run `./audit.sh --paranoid` and see `AUDIT PASSED (paranoid: …)`. Without the flag, only Lean's own kernel checks the proofs, which is faster and fine while working.
   - What `audit.sh` does:
     1. refuses uncommitted changes;
     2. **file check:** the audited files must be byte-identical to the commit in `AUDITED_COMMIT`, so a passing audit means the spec is still the one a human read. The list of audited files is at the top of `audit.sh`;
     3. clones HEAD into a temporary directory and runs the rest there, so no build output from the working tree is used;
     4. **`lake comparator`** (built into Lean 4.36): builds `Challenge` and `Solution` inside a `bwrap` sandbox, and checks that each theorem in `comparator.json` is proven in `Solution` with exactly the statement it has in `Challenge`, using only the permitted axioms, and that the kernel accepts the proof. `--paranoid` re-checks with five independent checkers;
     5. **`CheckChallenge.lean`**: the checks the comparator doesn't do (see "What's here").
   - Not a Lean expert? Also run `./attacks.sh`, which shows each step rejecting a concrete sabotage. It shows that those sabotages are caught, not that every possible trick is. The list of channels through which a trick could get in is in `notes/audit-integrity.md`, "Channels".
   - Not needed: `Toy/Categorize.lean` (the code) and `Solution.lean` (the proofs). The comparator checks the proofs against the audited statements, and `CheckChallenge.lean` checks the code mechanically.
3. **The wiring: does Python really run the proven code?** Not proven, only trusted, so read:
   - `build.sh`: it must compile `lean/.lake/build/ir/Toy/Categorize.c` (the C that Lean generates from `Categorize.lean`) into `build/libtoy.so`, the library Python loads. It builds only `Toy.Categorize`, so no agent-written file is built outside the sandbox.
   - `c/toy_shim.c` and `expenses_lean.py`: they must pass arguments and results across without changing them. `difftest.py` tests this but doesn't prove it.

## Results

- **It works.** `expenses_lean.py` prints the same report as `expenses.py`.
- **The theorem is proven** (no `sorry`), and it is stated about the exported function itself.
- **The audit can fail, at the right step.** `attacks.sh` runs the whole `audit.sh` on 12 sabotaged copies, each in its own throwaway git repo, plus an unchanged copy, which passes. Each sabotage is rejected, and the output shows the step meant to catch it. If a sabotage stops applying (say, after the code changes), the script reports it rather than skipping it. Last run Nov 28, 2026: all 13 verdicts as expected, with and without `--paranoid`.
  - In the agent's solution, after the audit was recorded; the comparator rejects:
    - the proof is `sorry`: "Illegal axiom detected: 'sorryAx'";
    - `axiom cheat : False`: "Illegal axiom detected: 'cheat'";
    - an easier claim (`theorem Toy.c1 : True`): statements don't match;
    - a fake `Toy.Spec.C1 := True` inside another namespace: statements don't match;
    - the solution defines its own `Toy.categorizeFFI` that always rejects: "Const does not match".
  - Build-time code in the solution (`#eval` probes): the audit passes, since the proof is honest, but writing project files, reading the home directory and network access are all blocked by the sandbox.
  - An edit to an audited file after the audit (`C1` changed to `True` in `Spec.lean`, with a trivial proof): the file check rejects.
  - In the code, already present when the audit was recorded (the code is frozen but not read, so the file check can't help). The comparator accepts each one, because it judges against the challenge as compiled; `CheckChallenge.lean` rejects:
    - a `macro_rules` line that turns the challenge's statement into `True`: statement check;
    - a `Toy.Toy.Spec.C1 := True`, which the statement `theorem Toy.c1 : Toy.Spec.C1 …` resolves to: statement check;
    - `notation` and `elab` declarations: syntax check;
    - the export renamed: export check;
    - `guess` gets `@[implemented_by evilGuess]`: compiled-code check.
  - Earlier layouts missed some of these: an audit file that imported the proofs could be fooled by name shadowing or macros in them. Details: `notes/audit-integrity.md`.
- **Differential test:** 0 mismatches in 100,000 cases each for seeds 0 and 1. Lone-surrogate inputs (about 11% of the generated cases) are skipped on purpose; see the findings below.
- **The test can fail:** run against the first, Unicode-aware version of the Python `categorize`, it reports 29,481 mismatches in 100,000 cases. So 0 mismatches means something.
- **Speed:** 100,000 calls of each version (200,000 total) plus the test's own overhead take about 0.9 s.
- **Memory:** loading the library and starting the Lean runtime adds about 21 MB resident (12 MB to 33 MB). It stays at 33 MB after 200,000 calls.
- **Valgrind:** no invalid reads or writes, nothing definitely lost. One "possibly lost" 288-byte block, which is the thread-local storage of a background thread that the Lean runtime starts at initialization: one-time, not per call.
  - Caveat: Lean objects come from Lean's own allocator, which valgrind doesn't see. The flat memory use over 200,000 calls is the evidence that Lean objects aren't leaking.

## Findings

1. **Same-looking functions, different contracts.** Python's `str.lower()` and `str.strip()` are Unicode-aware; Lean's `String.toLower` and `trimAscii` are ASCII-only, as documented. My first Lean version therefore didn't match the Python. Details and the general lesson are in `notes/python-lean-contract-gaps.md`.
   - **Decision:** changing the behaviour on purpose. The Python now normalizes ASCII-only too (`ascii_lower`, `ascii_trim`). This is a behaviour change to the original, accepted because the toy has no users. A real migration would have to justify it, measure it and document it.
   - A detail the differential test confirmed: Python's default `strip()` also removes `\v` and `\f`, which are ASCII but not Lean whitespace. So "ASCII-only" in Python had to mean `strip(" \t\r\n")`, not just "no Unicode."
2. **Lone surrogates can't cross the boundary.** A Python `str` can hold one (`"\ud800"`); UTF-8 can't encode it, and a Lean `Char` excludes surrogates. The glue rejects such input with `CategoryError`. The pure Python version may accept it, so this is a documented behaviour difference, and the differential test skips those cases instead of hiding them.
3. **NUL characters** are valid in Python strings but end a C string. The shim passes (bytes, length) in both directions, and the C test checks a string containing a NUL.
4. **`@[export]` parameters are always owned** (Lean FFI reference). The Lean function consumes its arguments; the C caller frees only the result. Lean 4.36 rejects `@&` (borrowed) on exports.
5. **Packaging is the real cost.** The stock static runtime (`libleanrt.a`) can't be linked into a shared library, because it uses local-exec thread-local storage. Python can only load shared libraries, so we link the toolchain's `libleanshared.so`: about 230 MB on disk, since it includes the whole Lean compiler. Options not yet tried:
   - build the Lean runtime from source with settings that allow use in a shared library;
   - compile the Lean code into a small standalone program and talk to it over a pipe;
   - accept the large dependency for a demo and say so.
6. **Toolchain details:**
   - In Lean 4.36 the module initializer is `initialize_<Package>_<Module>(uint8_t builtin)`, with no `world` argument, and `lean_initialize_runtime_module` isn't declared in `lean.h`.
   - `leanc` (Lean's bundled clang) has no `stdlib.h` in its sysroot, so the shim is compiled with the system `gcc`.
   - `String.trim` no longer exists; it's `trimAscii`, which returns a `Slice`.

## What is trusted

The proof covers `categorizeFFI` and nothing outside Lean. Trusted, not proven:
- The C shim (`c/toy_shim.c`, about 60 lines) and the Python glue (`expenses_lean.py`, about 40 lines): that they pass arguments and results across without changing them. `difftest.py` tests this but doesn't prove it.
- `build.sh`: that the library Python loads is compiled from `Categorize.lean` and nothing else.
  - The export check in `CheckChallenge.lean` doesn't cover this. It confirms that `categorizeFFI` is exported as `toy_categorize`, not that no other function is. Lean accepts two functions with the same `@[export]` name in different modules, and the audit build doesn't link, so it never sees the clash. Untested: whether linking both into one library fails with a duplicate symbol. Details: `notes/lean-learnings.md`, Nov 27.
- That the Python program uses `categorize` the way the theorem assumes. The theorem is about the Lean function, not about the program around it.
- Lean's compiler, runtime and kernel, and its three standard axioms. With `--paranoid`, the kernel's verdict is re-checked by five independent checkers.
- `lake comparator` and its `bwrap` sandbox: that they do what they say. Like the rest of the toolchain, they are shared by every Lean project and maintained by others.
- `AUDITED_COMMIT`: that only the user updates it, after reading the audited files.
- That the claims in `Spec.lean` say what we want, and that `Challenge.lean`, `CheckChallenge.lean`, `comparator.json` and `audit.sh` do what they say. That is the human audit.

## Not done yet

- Running `audit.sh` in CI: needs `bwrap` and unprivileged user namespaces on the runner. Untested.
- Threading: the runtime is initialized from Python's main thread, and calls from other threads haven't been tried (Lean may require `lean_initialize_thread` for them).
- macOS and Windows builds.
- A smaller runtime (finding 5).
