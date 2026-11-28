import Toy.Spec
import Toy.Categorize

/-!
# The proofs (written by the agent; not read by hand)

`lake comparator` checks that each theorem here proves exactly the statement of
the theorem with the same name in `Challenge.lean`, using only the axioms
permitted in `comparator.json`. That is why nobody needs to read this file.
-/

namespace Toy

/-- C1 (safety): an accepted category is on the allow-list. -/
theorem c1 : Toy.Spec.C1 Toy.categorizeFFI := by
  intro merchant declared allowed c h
  unfold categorizeFFI categorize at h
  by_cases hm : chooseCategory merchant declared ∈ allowed.toList <;> simp_all

end Toy
