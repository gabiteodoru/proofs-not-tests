import Toy.Spec

/-!
# Not audited: worked examples of the definitions in `Spec.lean`

Optional comprehension aids for whoever reads `Spec.lean`. Each `#guard` runs
the spec's definitions on one input when this file is built, and fails the
build if the result differs. They are examples, not proofs, and not part of
any audit verdict: the audit is reading `Spec.lean`, and `audit.sh` neither
builds nor checks this file.

Nothing imports this file. Build it with
`lake env lean Toy/SpecExamples.lean` (from `experiments/ffi-toy/lean`).
-/

open Toy.Spec

#guard lower "Blue CAFE 9!" = "blue cafe 9!"
#guard lower "É" = "É"                       -- only A–Z change
#guard trim "  food  " = "food"
#guard trim " a b " = "a b"                  -- inner spaces stay
#guard trim "\tfood" = "\tfood"              -- only spaces are trimmed
#guard trim "   " = ""
#guard normalize "  FOOD " = "food"
#guard guess "Blue Cafe" = "food"
#guard guess "Airline Cafe" = "food"         -- rule order decides, not position in the name:
                                             -- cafe (rule 1) beats airline (rule 3)
#guard guess "Bookshop" = "other"
#guard guess "" = "other"
#guard decide (IsSubstring "" "abc")
#guard decide (IsSubstring "abc" "abc")
#guard !decide (IsSubstring "ac" "abc")      -- contiguous only
