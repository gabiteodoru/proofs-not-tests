# proofs-not-tests

Coding needs to move from probabilistic QA to ironclad QA. This repo takes a real security bug, CVE-2026-48523 in PyJWT, and shows the difference between the two: tests passed on the vulnerable version, and a machine-checked Lean proof would not have.

The sharper version of the thesis: **move code correctness from sampling to proof, so that the only things left to trust are a small, human-auditable spec and trusted core.** Proofs are only as good as the spec they prove, so the spec is kept short, written in plain English first, and audited by a human. An AI agent writes the (much longer) proofs. This follows Leo de Moura's "AI writes Lean, humans audit."

## Status: work in progress

We're happy to show our work, including the parts that aren't finished. Please read each document with its status in mind:

- **`notes/cve-2026-48523.md`**: findings from reading PyJWT's source and git history, plus the security advisory.
  - The code facts were checked against the repository.
  - The advisory details were read through a summarizing fetch tool.
  - The spec in it is a **candidate**, not yet audited.
- **`Literature check AI-written specs and proofs (answers for Claude Code).md`**: a survey of prior work on AI-written specs and proofs.
  - Many 2026 papers were read through a summarizing tool, not as full PDFs.
  - Check numbers against the papers before citing them.
- **`verified-auth-benchmark-handoff.md`**: a **working draft** of research notes and the project plan.
  - Its section on 2026 breaches relies largely on secondary reporting, and some details are explicitly marked unverified.
  - Treat it as a lab notebook, not as a source.
- **Lean code (`LeanBugs/`)**: a project skeleton only, for now. The model, spec and proofs are next.

## Plan

1. Model PyJWT's signature-verification decision logic (`PyJWS._verify_signature`, about 30 lines) in Lean, with cryptography stubbed. Build a pre-fix version (2.12.1) and a post-fix version (2.13.0).
2. Write the security spec, for example "the algorithm that actually verified the signature is one the caller allowed."
3. Prove that the post-fix model satisfies the spec. Also prove that the pre-fix model **violates** it, using a concrete counterexample shaped like the published proof-of-concept.
4. Show the Lean model matches the real library: run differential tests of both Lean versions against PyJWT 2.12.1 and 2.13.0 on generated tokens.
5. Write it up, stating plainly what is trusted: the spec, the stubbed crypto, Lean's kernel and runtime, and the fact that the Lean model is not the Python code.

## Build

Requires [elan](https://github.com/leanprover/elan). Then:

```sh
lake build
```

## License

Apache-2.0. See `LICENSE`.
