import Toy.Categorize

/-!
# Proof that an accepted category is on the allow-list

Not human-audited. `Audit.lean` checks mechanically that this theorem proves
exactly the claim stated there, with no `sorry` and no extra axioms. This file
deliberately doesn't import `Audit.lean`: it states the claim in its own words,
and the check confirms the two say the same thing.
-/

namespace Toy

theorem accepted_is_allowed :
    ∀ (merchant : String) (declared : Option String) (allowed : Array String) (c : String),
      categorizeFFI merchant declared allowed = .ok c → c ∈ allowed := by
  intro merchant declared allowed c h
  unfold categorizeFFI categorize at h
  by_cases hm : chooseCategory merchant declared ∈ allowed.toList <;> simp_all

end Toy
