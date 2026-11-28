# Lean learnings from experiments

What Claude didn't know about Lean, or got wrong, and found out by running something. Each entry says what was run, so it can be repeated. Lean 4.36.0.

## Nov 27, 2026: name-shadowing demos on the toy's audit

Run on throwaway copies of `experiments/ffi-toy/lean/` in a scratchpad. The repo wasn't changed. The security consequences (open hole (1) and the fix) belong in handoff section 7b and in step 3 of its plan; this file records only the Lean facts.

### Things Claude didn't know, or predicted wrongly

- **`#print axioms` prints the full name it resolved, so `#guard_msgs` on its output also checks which declaration was found.**
  - Claude predicted that a fake `Toy.Audit.Toy.accepted_is_allowed` would get past check 2 of `Audit.lean`, just as it got past checks 1 and 3. It didn't: the message read `'Toy.Audit.Toy.accepted_is_allowed' depends on axioms: [...]`, not the expected `'Toy.accepted_is_allowed' ...`.
  - Confirmed by making the fake use the same three axioms: the build still failed, and the name was the only difference.
  - Limit: this protects only names that appear in a guarded message. In the planned layout, the attacker shadows the claim (`Toy.Spec.C1`), not the theorem, and check 2 prints the real theorem's real name. That attack passed every check.
- **A small proof can depend on no axioms at all.**
  - The fake proof `intro _ _ _ _ h; cases h` (`h : .error "no" = .ok c`, two different constructors) gave "does not depend on any axioms".
  - The real proof depends on `[propext, Classical.choice, Quot.sound]`. The axioms come from the tactics it uses (`by_cases`, `simp_all`), not from the theorem's statement. So the expected axiom list in check 2 is a fact about *this* proof: a different correct proof of the same claim could fail check 2.
  - To give the fake the same three axioms, `have _ := Classical.em True` (propext, Classical.choice) and `have _ : (fun x : Nat => x) = id := funext fun _ => rfl` (Quot.sound) were enough.
- **Building the modules didn't reject two functions with the same `@[export]` name.**
  - The real `Toy.categorizeFFI` and the fake `Toy.Audit.Toy.categorizeFFI` both had `@[export toy_categorize]`. Building `Toy.Audit` gave no error about it, and check 3 (`getExportNameFor?`) accepted the fake.
  - Not tested: whether linking both into one shared library fails with a duplicate symbol. It probably does, but the audit build doesn't link, so that wouldn't help the audit.

### Things Claude expected and confirmed

- **Redeclaring a name in a file that can see the original fails:** "`Toy.Spec.guess` has already been declared".
- **The same full name declared in two files that don't import each other:**
  - each file builds on its own;
  - any file importing both fails at the import line: "import Toy.Categorize failed, environment already contains 'Toy.Spec.guess' from Toy.Spec".
- **Inside `namespace A`, the name `B.x` is resolved as `A.B.x` first, if that exists.** So a declaration placed in another file under `Toy.Audit.Toy.…` takes the place of `Toy.…` everywhere in `Audit.lean`: in terms (check 1) and in double-backtick names (`` ``Toy.categorizeFFI ``, check 3).
- **`_root_.` turns off that lookup.** `_root_.Toy.Spec.C1` always means the top-level `Toy.Spec.C1`. With it, the claim-shadowing attack failed with "Type mismatch".
- **Code that refers to a module by name isn't affected by shadowing.** Check 4 looks up the module `` `Toy.Categorize `` and lists its declarations, so fakes in other modules don't change what it sees.
- **The kernel checker (`leanchecker`) doesn't catch shadowing.** It checks that every proof is valid, and the fakes are valid proofs of what they state. Shadowing changes *which* statement a human-readable line refers to; the kernel never sees that line as text.

## Nov 27, 2026: `lake comparator` on the toy

Run on a scratch copy of `experiments/ffi-toy/lean/`; the repo wasn't changed. Setup:
- `Challenge.lean` imports `Toy.Spec` and `Toy.Categorize` and states `theorem Toy.c1 : Toy.Spec.C1 Toy.categorizeFFI := sorry`.
- `Solution.lean` imports the same two modules plus `Toy.Proof`, and proves `Toy.c1` with `Toy.accepted_is_allowed`.
- `comparator.json` names the two modules, `"theorem_names": ["Toy.c1"]`, and permits the three standard axioms.
- Each module is a `[[lean_lib]]` in `lakefile.toml`.

### Things Claude didn't know

- **Lean 4.36 has the comparator built in, as `lake comparator` (and `lake check`).** It sandboxes with `bwrap` (bubblewrap), not `landrun` as the older standalone README says. `--paranoid` adds five external kernels: `leanchecker-paranoid`, `lean4lean`, `nanoda`, `con-leche`, `con-ron`. All five are in the toolchain's `bin/`.
- **The solution may import shared modules.** Challenge and solution both importing `Toy.Spec` and `Toy.Categorize` works, so the DRY layout survives.
- **By default the challenge is built from the project being judged, so editing a shared module gets through.** Changing `C1` to `True` in `Toy/Spec.lean` and proving it with `trivial` was accepted, because the challenge and the solution both saw the edited file. Building the challenge from the agent's checkout gives no protection.
  - Fix, confirmed: export the challenge from a trusted copy and judge against that export. With it, the same edit fails with "Const does not match between challenge and target 'Toy.Spec.C1'".
    - Export: `lake build Challenge`, then `lake env leanexport Challenge -- <names>`.
    - Judge: `lake comparator --challenge-from-export=<file>`.
  - The export must list the same names the comparator exports (it prints them as "Exporting #[...]"). Exporting only `Toy.c1` failed the honest solution with "Const not found in challenge 'semiOutParam'".
- **Inside the sandbox:**
  - the project source is read-only;
  - the real home directory is hidden, so reading `~/.bashrc` fails;
  - writes to home succeed but land on a throwaway filesystem, and nothing reached the real disk;
  - there is no network.
  - `#eval` in the solution runs during its build, inside the sandbox.
- **Timing:** about 12 s for the default kernel, about 35 s with `--paranoid` (each external kernel checked about 5,200 declarations).

### Attacks, and what stopped them (all with the trusted export)

- `sorry` in the solution: "Illegal axiom detected: 'sorryAx'".
- `axiom cheat : False`: "Illegal axiom detected: 'cheat'".
- Claim shadowing (a fake `Evil.Toy.Spec.C1 := True` inside `namespace Evil`): "Challenge and solution theorem statement do not match: 'Toy.c1'". No `_root_` needed: names are compared after resolution.
- The solution defines its own `Toy.categorizeFFI` that always rejects, making C1 trivially true: "Const does not match between challenge and target 'Toy.categorizeFFI'".
- Editing the shared `Toy/Spec.lean`: caught only with the trusted export (see above).

### Nov 28: the challenge's own imports can subvert it

Tested with a prototype's `run-attacks.sh` (in git history, removed Nov 28). Every attack in this section now runs through the toy's whole audit in `experiments/ffi-toy/attacks.sh`.

- **A macro in the implementation changes the challenge's statement.** One line appended to `Categorize.lean`, ``macro_rules | `(Toy.Spec.C1 $f) => `(True)``, made the challenge's `Toy.c1` state `True`, and the comparator accepted a trivial proof. It needed no `import Lean`: `macro_rules` is available from Lean's prelude.
- **`theorem Toy.c1 : …` reads its signature inside namespace `Toy`.** So `Toy.Spec.C1` in the signature resolves to `Toy.Toy.Spec.C1` if the implementation defines one. Tested: the statement became `Toy.Toy.Spec.C1 Toy.categorizeFFI`, and the comparator accepted. `_root_.` would stop this case, but not the macro.
- **Why the comparator can't catch these:** it checks that the solution proves the challenge's statement, whatever the challenge compiled to. A subverted challenge is still a consistent challenge.
- **A check that inspects the compiled challenge as data catches both.** A `lean --run` script that imports only `Lean`, and loads the challenge with `importModules #[{ module := `Challenge }] {} (loadExts := false)`, parses no source while the implementation's macros are active and runs no initializers. Then:
  - compare `(env.find? `Toy.c1).type` with `mkApp (mkConst `Toy.Spec.C1) (mkConst `Toy.categorizeFFI)`, using single-backtick names, which are literal names that are never resolved;
  - list the implementation module's constants (`env.header.moduleData[idx].constants`) whose type's head is `ParserDescr`, `TrailingParserDescr`, `Macro`, `Elab.Term.TermElab`, `Elab.Command.CommandElab`, `Elab.Tactic.Tactic`, `Parser.Parser` or `Parser.TrailingParser`.
  - Seen in tests: `macro_rules` creates `_aux_<Module>___macroRules_<...>` (type `Macro`); `notation` creates a `ParserDescr` plus a macro; `elab` creates a `ParserDescr` plus `_aux_…_elabRules_…` (type `TermElab`).
  - Now in the toy's audit: `experiments/ffi-toy/CheckChallenge.lean`.

### Not covered by the comparator

It checks kernel declarations only. `@[export]`, `@[implemented_by]` and `@[extern]` aren't part of them, so the toy's checks 3 and 4, and "the library Python loads is built from the challenge's implementation", are still needed. They can run on the trusted challenge alone, where shadowing from the solution can't reach them.
- Tested Nov 28: `getExportNameFor? env` and `Compiler.getImplementedBy? env` / `isExtern env` work on an environment loaded with `importModules … (loadExts := false)`. They returned `toy_categorize` and `[]` on the honest copy, and `toy_other` and `[Toy.guess]` on the toy's two implementation sabotages. The comparator accepted both sabotages.

## Nov 28, 2026: silencing the `sorry` warning for one declaration

- **`set_option warn.sorry false in` before a declaration turns off its "declaration uses `sorry`" warning, and only its.** Tested in a scratch file with three theorems proven by `sorry`, the option on the middle one: `lean` warned for the first and the third only.
- **The `sorry` is still recorded.** `#print axioms` on the silenced theorem printed `[sorryAx]`. So the option can't hide a `sorry` from the comparator's axiom check; it only removes the message.
- Used in the toy's `Challenge.lean`, where the `sorry` proofs are expected.
- Repeat: put `theorem a : 1 = 1 := sorry`, then `set_option warn.sorry false in` and `theorem b : 2 = 2 := sorry`, then `theorem c : 3 = 3 := sorry` and `#print axioms b` in a file, and run `lean` on it.
