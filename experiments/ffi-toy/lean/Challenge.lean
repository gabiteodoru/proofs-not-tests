import Toy.Spec
import Toy.Categorize

/-!
# Human-audited: the theorems to prove

Each theorem states one claim from `Toy/Spec.lean` about `Toy.categorizeFFI`,
the function Python calls. The proofs are `sorry` here; `lake comparator`
requires `Solution.lean` to prove exactly these statements.

Every theorem here must also be listed in `comparator.json` (`theorem_names`)
and in `../CheckChallenge.lean` (`expected`); a claim missing from either isn't
checked. C2–C4 join when the code meets SPEC.md.
-/

theorem Toy.c1 : Toy.Spec.C1 Toy.categorizeFFI := sorry
