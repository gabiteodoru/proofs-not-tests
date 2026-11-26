#!/usr/bin/env bash
# Evidence, not part of the audit. Sabotages a temporary copy of lean/ in five
# ways and checks that building Toy.Audit catches each one. The real files are
# never touched. Exits non-zero if any sabotage is missed.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/lean" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
failed=0

# Each sabotage runs inside the copy. If a sed pattern stops matching (because
# the files changed), the sabotage does nothing, the build passes, and the
# attack is reported MISSED: it can't silently become a no-op.
none()          { true; }
easier_claim()  { sed -i 's/→ c ∈ allowed := by/→ True := by/; /  unfold/d; s/  by_cases.*/  trivial/' Toy/Proof.lean; }
use_sorry()     { sed -i 's/  by_cases.*/  sorry/' Toy/Proof.lean; }
fake_claim()    { printf '%s\n' 'namespace Toy.Audit' \
                    'def AcceptedIsAllowed (f : String → Option String → Array String → Except String String) : Prop := True' \
                    'end Toy.Audit' >> Toy/Proof.lean; }
rename_export() { sed -i 's/@\[export toy_categorize\]/@[export toy_other]/' Toy/Categorize.lean; }
swap_compiled() { sed -i 's/^def guess (merchant : String) : String :=/def evilGuess (m : String) : String := "food"\n@[implemented_by evilGuess]\n&/' Toy/Categorize.lean; }

# check NAME SABOTAGE EXPECT [MARKER]: fresh copy, sabotage, build Toy.Audit.
# EXPECT=pass: the build must pass. EXPECT=fail: it must fail, and its output
# must contain MARKER (evidence that the intended check fired).
check() {
  rm -rf "$TMP/lean"; cp -r "$SRC" "$TMP/lean"
  if out="$(cd "$TMP/lean" && "$2" && lake build Toy.Audit 2>&1)"; then got=pass; else got=fail; fi
  if [ "$got" = "$3" ] && { [ "$3" = pass ] || grep -qF -- "$4" <<<"$out"; }; then
    echo "ok      $1"
  else
    echo "MISSED  $1"; failed=1
  fi
}

check "baseline: unchanged copy passes"              none          pass
check "easier claim (True) -> check 1"               easier_claim  fail "Type mismatch"
check "sorry -> check 2"                             use_sorry     fail "sorryAx"
check "fake claim in Proof.lean -> already declared" fake_claim    fail "has already been declared"
check "export renamed -> check 3"                    rename_export fail "toy_other"
check "compiled code swapped -> check 4"             swap_compiled fail "Toy.guess"
exit $failed
