# FFI smoke test: one Python function replaced by proven, compiled Lean

**Status: experiment, done Nov 25, 2026.** A toy run-through of the plan for PyJWT: take one function out of a Python program, rewrite it in Lean, prove a property, compile it, and call it from the otherwise unchanged Python.

## What's here

- `expenses.py`: the all-Python original, a small expense-report CLI. It reads `sample.csv` and prints totals per category.
- `lean/Toy/`, split so that a human audits only what is claimed:
  - `Categorize.lean`: the code. `categorize` rewritten in Lean, and `categorizeFFI`, the C-callable export, which is `categorize` itself with an `Array` in place of a `List`. Not read by hand.
  - `Proof.lean`: the proof, stating the claim in its own words. Not read by hand.
  - `Audit.lean`: **human-audited.** The claim (for any function of `categorizeFFI`'s shape: if it accepts a category, the category is on the allow-list) and four checks, each of which fails the build:
    1. the theorem in `Proof.lean` proves exactly this claim, about `categorizeFFI`;
    2. the proof uses no `sorry` and no axioms beyond Lean's standard three;
    3. `categorizeFFI` is exported as `toy_categorize`, the symbol the C shim calls;
    4. no definition in `Categorize.lean` has `@[implemented_by]` or `@[extern]`, which would make the compiled code differ from the proven definition. Scope: only these two attributes, only in that file.
- `audit.sh`: **human-audited.** Refuses to run on uncommitted changes, prints the commit, builds `Audit.lean` (running its checks), re-checks every `Toy` definition with `leanchecker`, and prints `AUDIT PASSED`. About 2 s.
- `attacks.sh`: evidence, not part of the audit. Sabotages a temporary copy of `lean/` five ways and checks that building `Audit.lean` catches each (see Results). Re-run it after changing a check or upgrading Lean. About 16 s.
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
./audit.sh                   # the proof audit (commit first)
./attacks.sh                 # shows the audit's checks can fail
```

## How to audit

Three parts, all on one commit. `audit.sh` refuses to run on uncommitted changes, so "passed" means it passed on exactly what you read.

1. **The claim: does it say what we want?** This is the core of the audit, and no script can do it.
   - Read the top half of `lean/Toy/Audit.lean`: the definition `AcceptedIsAllowed`, about 5 lines.
   - Judge whether it is the property you care about, and whether it is strong enough.
   - Known limit: it is a safety claim only. A `categorizeFFI` that rejected everything would also satisfy it.
2. **The proof: is the claim really proven, about the code Python calls?**
   - Read the bottom half of `Audit.lean` (four checks, each commented) and `audit.sh` (15 lines).
   - Run `./audit.sh` and see `AUDIT PASSED`.
   - Not a Lean expert? Also run `./attacks.sh`. A Lean expert knows from reading the checks what they catch. For anyone else, `attacks.sh` shows each check firing on a concrete sabotage. It shows that those five sabotages are caught, not that every possible trick is.
   - Not needed: `Categorize.lean` (the code) and `Proof.lean` (the proof). Lean checks them, and the checks above tie them to the claim.
3. **The wiring: does Python really run the proven code?** Not proven, only trusted, so read:
   - `build.sh`: it must compile `lean/.lake/build/ir/Toy/Categorize.c` (the C that Lean generates from `Categorize.lean`) into `build/libtoy.so`, the library Python loads.
   - `c/toy_shim.c` and `expenses_lean.py`: they must pass arguments and results across without changing them. `difftest.py` tests this but doesn't prove it.

## Results

- **It works.** `expenses_lean.py` prints the same report as `expenses.py`.
- **The theorem is proven** (no `sorry`), and it is stated about the exported function itself.
- **The audit checks can fail.** `attacks.sh` makes five deliberate sabotages in a temporary copy; each fails the build at the check meant to catch it, and an unchanged copy passes. If a sabotage stops applying (say, after the code changes), the script reports it as missed rather than skipping it.
  - the proof proves an easier claim (conclusion `True`): check 1;
  - the proof is `sorry`: check 2;
  - `Proof.lean` defines its own, easier `Toy.Audit.AcceptedIsAllowed`: "already declared", and check 1;
  - the export is renamed: check 3;
  - `guess` gets `@[implemented_by evilGuess]`: check 4.
  - An earlier layout, with the claim and the checks in separate files, missed the fake-claim sabotage: check 1 compared against the fake. Keeping the claim in the file that does the checking removed that hole.
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
- That the Python program uses `categorize` the way the theorem assumes. The theorem is about the Lean function, not about the program around it.
- Lean's compiler, runtime and kernel, and its three standard axioms.
- That the claim in `Audit.lean` says what we want, and that its checks and `audit.sh` do what they say. That is the human audit.
## Not done yet

- Threading: the runtime is initialized from Python's main thread, and calls from other threads haven't been tried (Lean may require `lean_initialize_thread` for them).
- macOS and Windows builds.
- A smaller runtime (finding 5).
