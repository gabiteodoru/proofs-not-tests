import Lean
import Toy.Categorize
import Toy.Proof

/-!
# Human-audited: what is claimed, and the checks that it is proven

This is the only Lean file a human needs to read. `../../audit.sh` builds it;
if any check below fails, the build fails. The code (`Categorize.lean`) and the
proof (`Proof.lean`) are not read by hand.
-/

namespace Toy.Audit

/-- The claim, for any function with the shape of `categorizeFFI`:
if it accepts a category `c` (returns `.ok c`), then `c` is on the allow-list.
Arguments: merchant name, declared category (optional), allow-list. -/
def AcceptedIsAllowed (f : String → Option String → Array String → Except String String) : Prop :=
  ∀ merchant declared allowed c, f merchant declared allowed = .ok c → c ∈ allowed

/-! ## Checks -/

-- Check 1: the theorem in `Proof.lean` proves exactly the claim above, about
-- `categorizeFFI`. This line doesn't compile if it proves anything else.
example : AcceptedIsAllowed Toy.categorizeFFI := Toy.accepted_is_allowed

-- Check 2: the proof has no `sorry` and assumes nothing beyond Lean's three
-- standard axioms. `#print axioms` lists every assumption the proof rests on,
-- through every file; a `sorry` would show up as `sorryAx`. `#guard_msgs`
-- fails the build unless the output equals the comment just above it.
/-- info: 'Toy.accepted_is_allowed' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms Toy.accepted_is_allowed

-- Check 3: `categorizeFFI` is exported to C as `toy_categorize`, the symbol
-- the C shim calls. So the function in the claim is the one Python reaches.
open Lean in
/-- info: some `toy_categorize -/
#guard_msgs in
#eval show CoreM _ from do return getExportNameFor? (← getEnv) ``Toy.categorizeFFI

-- Check 4: nothing in `Categorize.lean` has its compiled code swapped out.
-- `@[implemented_by]` or `@[extern]` would make the compiled program run
-- different code from the definition the proof is about. Expected: none ([]).
open Lean in
/-- info: [] -/
#guard_msgs in
#eval show CoreM (List Name) from do
  let env ← getEnv
  let some idx := env.getModuleIdx? `Toy.Categorize | throwError "module not found"
  return env.header.moduleData[idx.toNat]!.constNames.toList.filter fun n =>
    (Compiler.getImplementedBy? env n).isSome || isExtern env n

end Toy.Audit
