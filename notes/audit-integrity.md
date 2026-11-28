# Audit integrity: is the proven claim the one a human audited?

Design issues found on Nov 27–28, 2026, while testing the toy's audit. The Lean facts behind them, with the commands to repeat each test, are in `notes/lean-learnings.md`. The toy's audit now implements the fixes (Nov 28): `experiments/ffi-toy/audit.sh`, with every attack in `experiments/ffi-toy/attacks.sh`. This note records what the issues mean for the project's design and argument, and the plan that was followed (last section).

## Summary

- **The core point, agreed with the user (Nov 28):** without the comparator, an agent can cheat by adding to the proof files alone, which nobody reads, while leaving every human-audited file unchanged. The comparator closes this: proof files can affect the verdict only by being valid proofs of the audited statements.
  - "Cheat" includes accidents: a misleading definition produced while trying to make a proof go through.
  - The comparator is the standard way to close this, not the only one (reading every proof also works). What doesn't work is the toy's current layout, an audit file that imports the proofs.
- **Consequences**, which are the same argument:
  - *Readers:* the verdict depends only on the current files, not on how the proofs were produced. A reader doesn't need to trust that anyone watched the agent.
  - *Scale:* the method doesn't need a human to keep up with the agent's edits, which is de Moura's thesis.
- **Separate threats, not handled by the comparator:**
  - changes to the human-audited files (Issue 3);
  - the implementation, which the challenge imports, subverting it (Issue 5);
  - the compiled program differing from the definitions (Issue 4).

## Roles

- **The human:** writes or approves the spec (`SPEC.md`, `Spec.lean`) and audits it. This is the only part a person must read.
- **The implementation:** `Categorize.lean`, and later the PyJWT model. Written by us, fixed before proving starts, and not read for correctness (the proofs cover that).
- **The proving agent:** an LLM session (for example a separate Claude Code session) given the spec and the code, told to prove the claims, and logged for the write-up. It writes the solution (the proof files). It's untrusted: it can make mistakes, or weaken the claim to finish.
- **Lean's kernel:** a checker, not a writer. It accepts or rejects proofs. It's trusted; `--paranoid` re-checks its verdict with five independent checkers.
- **The comparator (`lake comparator`):** the judge. It confirms that the solution proves the human's statements, using only the permitted axioms, and that the kernel accepts it.

## Issue 1: what an audited line means can depend on files the agent wrote

- In the toy's current layout, `Audit.lean` imports `Proof.lean`. So code the agent wrote is loaded while the audit's checks are read.
  - **Name shadowing:** a fake `Toy.Audit.Toy.Spec.C1` makes the line `Toy.Spec.C1` in the audit file mean the fake. This passed every check. `_root_.` fixes this one case.
  - **Macros:** an imported file can change how later lines are parsed, even what a command like `#print axioms` does. So `_root_` is only sound once this is closed.
  - The kernel and `leanchecker` can't catch either attack. The fakes are valid proofs of what they state, and the kernel never sees the audit file as text.
- **The trusted list has to include this.** "Humans audit the spec" needs one more condition: the spec is read in a context the prover can't change.
- **Fix:** the comparator, which is built into Lean 4.36. It builds and exports both sides inside a sandbox, never loads the solution's compiled files into its own process, and compares declarations after names are resolved. In the experiment, it rejected the shadowing attack without `_root_`.
- **For the write-up:** with the comparator, this caveat shrinks to one more item on the trusted list ("the comparator and its sandbox do what they say"). The list stays finite and auditable.

## Issue 2: the axiom check pinned details of one particular proof

- The toy's check 2 requires the *exact* axiom list `[propext, Classical.choice, Quot.sound]`. That list comes from the tactics the proof happens to use (`by_cases`, `simp_all`), not from the claim.
- So a different correct proof that uses fewer axioms fails the audit. The demo's fake proof used none. That's a flaky check, and it works against the idea that the agent can redo proofs freely while the audited part stays fixed.
- **Fix:** an allow-list (every axiom used must be one of the three). The comparator's `permitted_axioms` setting does exactly this. It still rejects `sorry` (which shows up as `sorryAx`) and made-up axioms such as `axiom cheat : False`; both were tested.

## Issue 3: the judged spec must be the audited spec

- The human reads one version of the spec. By default, the comparator judges whatever version is in the project when it runs, building the challenge from the same checkout as the solution. Nothing ties the two versions together.
- Tested: changing `C1` to `True` in the shared `Toy/Spec.lean` and proving it with `trivial` was accepted.
- **Scenarios**, most likely first:
  1. **The agent weakens the spec while trying to finish.** It needs a shell and write access to edit the solution and run builds, so nothing stops it editing the spec too. This needs no malice, only the path of least resistance. Handoff section 7b already lists spec weakening as a risk.
  2. **The change is lost in a big diff.** A one-line edit to the spec, the implementation or the lakefile, among many proof changes. The implementation and the lakefile are part of the challenge but not reviewed by design, so edits there are the easiest to miss.
  3. **Later commits.** In a long-lived project, or in the follow-up experiment "does a proof gate survive ongoing changes?" (handoff section 6b), people and agents keep committing after the audit. A green check must mean "the spec is still the audited version", not "whatever spec is in this commit is proven".
  4. **Build outputs.** The agent's builds write `.lake/`, which holds compiled copies of the spec and the implementation. Read-only sources don't protect these.
- **Fixes**, to use together:
  - **Trusted challenge export** (tested). Build the challenge from our own copy at the audited commit, export it with `leanexport`, and judge with `lake comparator --challenge-from-export=<file>`. With it, the spec edit was rejected.
  - **File check** (planned, in `audit.sh`). Before judging, require the audited files (spec, the implementation the challenge imports, lakefile, `comparator.json`) to be byte-identical to the audited commit: `git diff --exit-code <audited-commit> -- <files>`, or stored hashes. A change fails the gate and means a re-audit. Its error names the changed file, which is clearer than a comparator mismatch.
  - **Sandbox the agent** (planned; a convenience, not part of the trusted list). Make the audited files read-only for the agent, through file ownership by another user or a read-only mount. Then the agent learns immediately that it can't weaken the spec, rather than after a wasted session.
    - Claude Code's own permission rules (for example, denying `Edit` on a path) are weaker than OS permissions: the agent can still write the file through a shell command. For enforcement, use the OS.
  - In the plan below, the file check plus a clean clone already make the challenge the audited one, so the trusted export becomes optional.
- **Why the file check is still needed with a sandbox:**
  - *The verdict shouldn't depend on how the agent was set up.* A reader should be able to clone the repo, run `audit.sh`, and trust the result without trusting our account of the agent's environment. That keeps the sandbox off the trusted list.
  - *Setups fail quietly.* Permissions go on the wrong directory, a container runs as root, the agent has `sudo`. A failed hash check is loud.
  - *Build outputs are writable* (scenario 4). Judging from a clean clone with a trusted export avoids relying on them.
  - *Not every change comes from a sandboxed agent* (scenario 3).

## Issue 4: what the comparator doesn't check

- It checks kernel declarations only. `@[export]`, `@[implemented_by]` and `@[extern]` aren't part of them.
- So the toy's checks 3 (`categorizeFFI` is exported as `toy_categorize`) and 4 (no compiled code swapped in) are still needed, and so is "the library Python loads is built from the challenge's implementation".
- These checks get simpler: they run on the trusted challenge alone, which imports nothing the agent wrote, so shadowing can't reach them. Tested (Nov 28): both work on the challenge loaded as data, in `CheckChallenge.lean`, and catch the toy's two existing implementation sabotages, which the comparator accepts.
- Check 3 confirms that `categorizeFFI` carries the export name, not that no other function does. Lean accepts two functions with the same `@[export]` name in different modules (see the toy README, "What is trusted").

## Issue 5: the implementation, which the challenge imports, can subvert it

- The challenge imports the implementation (`Categorize.lean`) so that its statements can mention `categorizeFFI`. By design, nobody reads the implementation for correctness; the proofs cover that.
- But the implementation can change how the challenge's statement line is read. Both cases were tested (details in `notes/lean-learnings.md`, Nov 28):
  - a `macro_rules` line in the implementation turned the statement into `True`;
  - a `Toy.Toy.Spec.C1 := True` in the implementation shadowed the claim, because `theorem Toy.c1` reads its signature inside namespace `Toy`.
- In both cases the comparator accepted a trivial proof. The challenge itself was subverted, and the comparator only checks that the solution matches the challenge.
- This applies whoever writes the implementation: us, or an agent before the implementation is frozen.
- **Fix (prototyped and tested):** `CheckChallenge.lean` loads the compiled challenge as data, with no source parsed while the implementation's macros are active. It then checks:
  - each statement is exactly the intended term, written from literal names;
  - the implementation module declares no syntax (macros, notation, parsers, elaborators).
- So the implementation still needs no reading for correctness. It only has to pass a mechanical "defines no syntax" check, and the statements are checked as terms, not as text.

## What a reader has to check

For someone who clones the repo and wants to trust the result:
- **Read:**
  - `Spec.lean` (the definitions and claims);
  - the expected statements, in `Challenge.lean` and in `CheckChallenge.lean`;
  - `comparator.json` (which theorems, which axioms are allowed);
  - `audit.sh`, and the checks file for checks 3 and 4.
- **Trust without reading:** the Lean toolchain, the comparator and `bwrap`. These are shared by every Lean project and maintained by others ("evidence reused", handoff section 6).
- **Neither read nor trust:** the proof files, and the implementation (beyond the mechanical syntax check; the proofs cover its correctness).
- The file check against the audited commit is for us, not for the reader: it protects an audit from later changes. A reader doing their own audit reads the current files directly.

## Channels: every way untrusted content could reach the verdict

Why this list exists: finding attacks one at a time has the same weakness as testing (you stop when you run out of ideas). Listing the *channels* through which untrusted content (agent-written proofs, or an implementation nobody reads) could affect the verdict is reviewable for completeness, and each channel can be closed structurally. This is our best list as of Nov 28, 2026. It isn't proven complete; review it, and add to it when something new turns up.

None of the issues so far was a flaw in Lean's proof checking: every fake was a valid proof of what it stated. They were all at the edges listed here.

Status words: **closed (tested)** means an attack was run through the whole audit and caught (`experiments/ffi-toy/attacks.sh`); **closed (planned)** means the design closes it but it isn't implemented or tested yet; **trusted** means we rely on it without checking it.

1. **Proof files into what humans read.** An audit file that imports the proofs lets them shadow names or redefine syntax (Issue 1).
   - Closed (tested): nothing humans read imports the proofs. The comparator compares compiled terms, inside a sandbox.
2. **Implementation into the challenge.** The challenge imports the implementation, so the implementation can change what the challenge's statement means (Issue 5).
   - Closed (tested): `CheckChallenge.lean` checks each statement as a term built from literal names, and that the implementation declares no syntax. The syntax check recognizes syntax by declaration type; that list covered every attack tried but isn't proven complete. The statement check is the main guard.
3. **The spec's own meaning.** `Spec.lean` imports nothing, so its text means what Lean's core language says it means.
   - Trusted: Lean's core language and prelude, as for any language.
   - Closed (tested): the file check keeps its text, including the import lines, as audited. A mechanical "imports nothing" check would be cheap to add.
4. **Which files are judged.** An edited spec, implementation or lakefile is judged against itself (Issue 3).
   - Closed (tested): the file check against the audited commit (`edit-spec` in `attacks.sh`).
   - Trusted: the record of the audited commit; only the user updates it.
5. **Build outputs.** The agent's builds write `.lake/`, which holds compiled copies of the spec and the implementation.
   - Closed (implemented): every audit step after the file check runs in a clean clone. Whether Lake would actually reuse a tampered build output is untested; the clean clone avoids depending on the answer.
6. **Agent code running during builds.** Lean runs `#eval` and macros while compiling.
   - Closed (tested): the comparator builds inside `bwrap`. Writing project files, reading the home directory and network access were blocked.
   - Closed (tested): `CheckChallenge.lean` doesn't import the solution, loads the challenge with `loadExts := false`, and runs no initializers.
   - Closed (implemented): `build.sh` builds only `Toy.Categorize`, so the shipped library never builds agent files.
   - Outside the audit: the user's own interactive builds run agent code unsandboxed. That's a risk to the user's machine, not to the verdict.
7. **Axioms.** A proof can assume anything through `sorry`, a made-up axiom, or `native_decide` (which in 4.36 creates a new axiom for each proof, such as `t._native.native_decide.ax_1_1`; checked).
   - Closed (tested for `sorry` and a made-up axiom): the comparator's allow-list permits only `propext`, `Classical.choice` and `Quot.sound`. `native_decide`'s axiom is outside the list, so it would be rejected too (not run through the comparator).
8. **Kernel bugs.** A proof accepted only because of a bug in Lean's kernel.
   - Trusted, with independent checks: `--paranoid` re-checks with `leanchecker-paranoid`, `lean4lean`, `nanoda`, `con-leche` and `con-ron`. A false proof would have to get past all of them.
9. **Which claims are judged.** The comparator judges only the theorems named in `comparator.json`, and `CheckChallenge.lean` checks only the statements it lists. A claim missing from either isn't checked.
   - Closed (implemented): both files are on the file check's list, and must name every claim (C1 now; C2–C4 later). `Challenge.lean` says so in its header.
10. **Logic to compiled program.** The kernel checks definitions, not machine code.
    - Closed (tested): check 3 (export name) and check 4 (no `@[implemented_by]` or `@[extern]`), in `CheckChallenge.lean`.
    - Trusted: Lean's compiler (Lean to C) and the C compiler. The largest unverified piece.
11. **Compiled library to Python.** The C shim and the Python glue.
    - Trusted: tested by `difftest.py`, not proven (toy README, "What is trusted").
12. **The toolchain.** Which Lean version runs the audit.
    - Trusted: the Lean release, pinned by `lean-toolchain`, which is on the audited-file list.
13. **The spec says what we mean.** No tool can check this.
    - The human audit. Planned help: a check that `Valid` is satisfiable, so that C3 and C4 can't be vacuously true (toy step 2 in handoff section 7b).

How this list was used: the implementation-into-challenge channel (2) was found by going through the imports one by one while writing the plan, not by inventing an attack. Red-teaming is a complementary check. Ask an agent, in a logged session, to make `audit.sh` pass with a false claim; any success means a channel is missing from this list. That session would also be write-up material.

## Why interactive approval doesn't replace this

The user works interactively and approves each code change, so they would see an agent editing the audited files. That helps, but:
- **It doesn't catch Issue 1 or Issue 5.** Those attacks add ordinary-looking definitions to files the user deliberately doesn't read (proofs, implementation). Catching them by watching means reading and understanding every proof edit, which is auditing the proofs.
- **Readers can't see the approvals.** "I watched carefully" can't be checked by anyone else, which is exactly the kind of trust the write-up argues against. With the comparator and the checks, a reader runs `audit.sh` and the session process is irrelevant.
- **It doesn't scale.** Long proving sessions have many edits, including shell commands, where a one-line change is easy to miss.

## Scope for this project

- **Do:** the comparator, `CheckChallenge.lean`, checks 3 and 4, and the file check against the audited commit, all in `audit.sh`. Cheap, and they make the write-up's claim checkable by someone who wasn't there.
- **Skip:** sandboxing the agent (interactive approval already covers it, and it was never on the trusted list).
- **Skip:** a team process. Mention it in the write-up as the next step for a real team, citing the prior work below once verified.

## Team level: who may change the spec

Scenario 3 turns this into a team question: which teammates may change the spec, and how changes get reviewed and approved.

- **Not every change comes from a sandboxed agent.** After the audit, the spec, the implementation the challenge imports or the lakefile can change through:
  - a teammate's commit, made in good faith (a "small cleanup" of a definition);
  - a refactor that renames or moves definitions the claims depend on;
  - a merge. Two branches can each change the spec harmlessly while the combination changes what it means. Neither branch's review shows the combined result.
  - Sandboxing the agent doesn't apply to any of these. The file check does: it compares against the audited commit, however the change arrived.
- **What a team process has to settle:**
  - *Who may change the audited files.* For example, only named spec owners, enforced by CODEOWNERS and branch protection.
  - *Who may approve a change to them.* Not the author (two-person rule). For an AI-written change, a human who reads the spec diff, not only the green check.
  - *A spec change means a re-audit, not just a passing build.* An approved spec change should update the audited commit only after someone has read the new spec.
  - *Who may move the audited-commit pointer.* The file check is only as strong as the record of which commit was audited. If anyone can update that record, for example a hash in the repo, anyone can bypass the check. So the record itself needs the same protection as the spec: owned, reviewed, and preferably signed (as in in-toto, below).
  - *What CI enforces vs what people do.* CI can enforce "the audited files are unchanged since the audited commit" and "the comparator passes". Only a person can confirm "the new spec says what we mean".

Prior work exists in several fields.

**Unverified:** the list below was written from memory. Check each citation before using it in the write-up. Research Claude could verify them and add them to the literature-check doc, which doesn't cover this angle yet.

- **Software engineering:**
  - CODEOWNERS plus branch protection (GitHub, GitLab): a pull request touching given paths needs approval from named owners. "Changes to the spec need the spec owner's sign-off" is a one-line rule.
  - Separation of duties, or the two-person rule: the author of a change can't approve it.
- **Software supply chain:**
  - SLSA (Supply-chain Levels for Software Artifacts): higher levels require two-person review and verifiable records of how an artifact was built.
  - in-toto: a signed layout says which person or tool may perform each step, and verification checks that each step was done by the right party with the expected inputs. "The spec is the audited one, the proof came from the agent, the judge used the trusted export" maps onto it closely.
- **Formal verification in industry:**
  - Chudnov et al., "Continuous Formal Verification of Amazon s2n", CAV 2018: proofs of a TLS library run in CI on every commit, maintained alongside developers who aren't proof experts. The closest prior work to the follow-up experiment in handoff section 6b.
  - seL4: years of proof maintenance on a changing kernel, with published studies of proof effort and change cost (Klein, Staples, Matichuk and colleagues).
  - Ringer et al., "QED at Large: A Survey of Engineering of Formally Verified Software" (2019): proof engineering, including maintenance and how proofs break when code or specs change.
- **The Lean community:** the Liquid Tensor Experiment, and later projects such as Buzzard's FLT project, kept the main statement in a small file that people check by hand. The comparator grew out of the same idea. These projects rely on maintainer review and CI.
- **Possibly less studied** (to check): combining these when an AI agent is an untrusted contributor that can quietly weaken the spec, and the evidence needed is "this proof came from the agent, and it proves the statement the humans approved". The parts are mature; we haven't seen them combined for this setting.
- **For the write-up:** one or two sentences. Binding the audited spec to the judged spec is the problem SLSA and in-toto solve for builds; CODEOWNERS is the team-level version. Keep the project's own mechanism small: a trusted export plus a file check.

## Plan: moving the toy to the comparator (toy step 3 in handoff section 7b)

Status (Nov 28): **done**, steps 1–5, in the same session the user agreed to it. The prototype it started from was removed (it's in git history). Decisions taken along the way: `Toy/Proof.lean` merged into `Solution.lean` (the only agent-written file); `SPEC.md` and `lean/Toy.lean` added to the audited files; `audit.sh` and `attacks.sh` take `--paranoid` (off by default, so the attack suite is fast; use it for a real audit); implementation attacks are applied *before* the audit is recorded (the implementation is frozen but not read, so the file check can't help), the rest after. Step 6 (CI) is still open. The record below is the plan as written.

1. **Layout**, in `experiments/ffi-toy/lean/`:
   - Keep `Toy/Spec.lean` (human-audited) and `Toy/Categorize.lean` (the implementation; frozen, not read for correctness).
   - Add `Challenge.lean`, `Solution.lean` and `comparator.json`, and the two `[[lean_lib]]` entries in `lakefile.toml`, from the prototype.
   - Put `CheckChallenge.lean` outside every `lean_lib`: it's a script run with `lake env lean --run`, not a module. For example `experiments/ffi-toy/CheckChallenge.lean`.
   - Delete `Toy/Audit.lean`, and its import in `Toy.lean`.
   - Agent-written files: `Solution.lean` and `Toy/Proof.lean` (the prototype's solution imports `Toy.Proof`). Keeping or merging them is the user's call; either way, list the agent-written files explicitly in the README.
   - Start with C1 only: the existing proof proves it. C2–C4 join `Challenge.lean`, `comparator.json` (`theorem_names`) and `CheckChallenge.lean` (the expected statements) when toy step 4 changes the implementation to meet SPEC.md.
2. **`build.sh`: build only the implementation.** Today it runs `lake build`, which builds the default targets. After the move, those include the agent's files, so the agent's code (for example `#eval`) would run outside the sandbox, and the shipped library's build would depend on agent files. Change it to `lake build Toy.Categorize`; the library needs nothing else.
3. **`audit.sh`, in order:**
   1. Refuse uncommitted changes (as today).
   2. **File check.** The audited files must be unchanged since the audited commit: `git diff --exit-code <audited-commit> HEAD -- <files>`.
      - Audited files: `lean/Toy/Spec.lean`, `lean/Toy/Categorize.lean`, `lean/Challenge.lean`, `lean/comparator.json`, `lean/lakefile.toml`, `lean/lake-manifest.json`, `lean/lean-toolchain`, `CheckChallenge.lean`, `build.sh`, `audit.sh`. The implementation is on the list because it's frozen, not because it's read.
      - Record the audited commit in a file, for example `experiments/ffi-toy/AUDITED_COMMIT`. Only the user updates it, after reading the changed files; that update is the re-audit.
   3. **Clean clone.** Clone HEAD into a temporary directory and run the remaining steps there, so no build output from the working tree is used. The agent's builds write `.lake/` (scenario 4 in Issue 3). Lake reuses existing build outputs whose recorded source hash matches, so a tampered `.olean` might be used without a rebuild. This is reasoning, not tested; the clean clone avoids depending on it either way.
   4. **`lake comparator --paranoid`** in the clean clone. Because the file check passed, the challenge built there is the audited one.
      - Recommended: the comparator's default mode, which builds the challenge itself. That avoids the trusted export's hand-copied name list.
      - Alternative: a trusted export from a clone of the audited commit (tested in the prototype); needs the name list (see the prototype's known limits).
   5. **`CheckChallenge.lean`** in the clean clone: `lake build Challenge`, then `lake env lean --run <path>/CheckChallenge.lean`.
   6. Drop `lake env leanchecker Toy`: the comparator replays the solution through the kernel, and `--paranoid` through five more checkers.
4. **`attacks.sh`:** replace with an adapted `run-attacks.sh` that runs the whole `audit.sh` on each sabotaged copy, not each tool separately, so it tests the real gate.
   - Include the prototype's attacks.
   - Include the old sabotages from today's `attacks.sh`. `use_sorry`, `rename_export` and `swap_compiled` are covered; `easier_claim` and `fake_claim` become the solution-side attacks.
   - Add one attack for the file check: edit `Toy/Spec.lean` and commit it without updating `AUDITED_COMMIT`. Expected: the audit stops at step 2.
5. **Toy README:**
   - rewrite "How to audit" for the new layout, using "What a reader has to check" above;
   - update "What is trusted": add the comparator and `bwrap`, and remove the hand-written checks;
   - say that the sandbox needs Linux (`bwrap`), and that an audit takes about 35 seconds with `--paranoid` (measured on the prototype).
6. **CI (open item in 7b):** running `audit.sh` in GitHub Actions needs `bwrap` and unprivileged user namespaces on the runner. Untested. Recent Ubuntu versions restrict user namespaces through AppArmor, so it may need a setting change on the runner.
7. **Afterwards:** use the same layout for PyJWT. The bullets in 7b's "Next task" that describe the old layout follow this plan instead.
