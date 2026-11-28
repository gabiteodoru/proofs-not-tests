import Toy.Spec
import Toy.Categorize

/-!
# Human-audited: the theorems to prove

Each theorem states one claim from `Toy/Spec.lean` about `Toy.categorizeFFI`,
the function Python calls. The proofs are `sorry` here; `lake comparator`
requires `Solution.lean` to prove exactly these statements.

Every theorem here must also be listed in `comparator.json` (`theorem_names`)
and in `../CheckChallenge.lean` (`expected`); a claim missing from either isn't
checked. C2–C4 join when the implementation meets SPEC.md.

Each theorem is preceded by `set_option warn.sorry false in`, which turns off
the "declaration uses `sorry`" warning for that one theorem only, because the
`sorry` is expected here. It doesn't hide the `sorry` from the comparator,
which still sees the axiom `sorryAx` (tested; `notes/lean-learnings.md`).
-/

set_option warn.sorry false in
theorem Toy.c1 : Toy.Spec.C1 Toy.categorizeFFI := sorry
