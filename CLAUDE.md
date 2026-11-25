# proofs-not-tests: start here

A public portfolio repo: a Lean proof that the fix for PyJWT CVE-2026-48523 (an algorithm allow-list bypass) is correct, and that the bug existed before it. "AI writes the Lean proofs, humans audit the spec" (Leo de Moura).

## What to read, in order

1. `verified-auth-benchmark-handoff.md`, **section 7b only** ("Session state"): what's done, what's next, how the user works. Read section 6 too if the task is about the plan or the write-up.
2. `notes/cve-2026-48523.md`: the bug, the decision logic, the spec (decisions D1–D6, agreed with the user; don't reopen them unless asked), and the Lean modeling plan.
3. Only when the task touches it:
   - `experiments/ffi-toy/README.md`: calling compiled Lean from Python (build steps, ownership rules, packaging limits).
   - `notes/python-lean-contract-gaps.md`: Python vs Lean primitives with different contracts.

## Usually skip

- Handoff sections 1–5 and 6b: background research and a backup plan.
- `Literature check AI-written specs and proofs (answers for Claude Code).md`: prior-work survey; read it for the write-up only.
- `vendor/` (gitignored clones of PyJWT and lean-zip). For PyJWT, read the specific function at the specific commit (pre-fix `95791b1^`, fix `95791b1`, `jwt/api_jws.py`, `_verify_signature`), not whole files.

## Working rules

- Keep session state and repo rules in handoff section 7b, not here; this file only points. Update 7b at the end of a session.
- Each fact has one home; elsewhere, summarize in a line and point to it.
- Lean 4.36.0. `lake build` at the root builds the main library; `experiments/ffi-toy/build.sh` builds the toy.
