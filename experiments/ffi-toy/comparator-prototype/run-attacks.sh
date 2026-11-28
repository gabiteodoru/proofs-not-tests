#!/bin/bash
# Prototype, not wired into the toy's audit: runs every attack in attacks/ against
# `lake comparator` and CheckChallenge.lean, on throwaway copies of ../lean, and
# checks each verdict is the expected one. The repo isn't modified.
# Usage: ./run-attacks.sh            (about 90 seconds; needs bwrap)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LEAN=$HERE/../lean
W=$(mktemp -d)
echo "work dir: $W"

# The names `lake comparator` exports for this challenge (from its "Exporting #[...]"
# line). The trusted export must contain the same ones, or honest solutions fail
# with "Const not found in challenge".
NAMES="Quot Quot.mk Quot.lift Quot.ind Toy.c1 propext Quot.sound Classical.choice Nat.add Nat.sub Nat.mul Nat.pow Nat.gcd Nat.div Nat.mod Nat.beq Nat.ble Nat.land Nat.lor Nat.xor Nat.shiftLeft Nat.shiftRight String.ofList Char.ofNat List eagerReduce Nat String String.mk Char optParam autoParam semiOutParam outParam"

# Base project: the toy's spec, code and proof, plus the prototype's challenge/solution.
B=$W/base
mkdir -p "$B"
cp -r "$LEAN/Toy" "$LEAN/lean-toolchain" "$LEAN/lake-manifest.json" "$B/"
rm "$B/Toy/Audit.lean"
cp "$HERE"/{lakefile.toml,Challenge.lean,Solution.lean,comparator.json} "$B/"
printf 'import Toy.Spec\nimport Toy.Categorize\nimport Toy.Proof\n' > "$B/Toy.lean"
(cd "$B" && lake build Challenge >/dev/null 2>&1 && lake env leanexport Challenge -- $NAMES > "$W/challenge.ndjson") \
  || { echo "base build or export failed"; exit 2; }

fails=0
# expect NAME TOOL EXPECTED_EXIT : TOOL is "trusted" (comparator vs trusted export),
# "default" (comparator building the challenge from the copy) or "check" (CheckChallenge).
expect() {
  local name=$1 tool=$2 want=$3 out code
  cd "$W/$name"
  case $tool in
    trusted) out=$(lake comparator --challenge-from-export="$W/challenge.ndjson" 2>&1) ;;
    default) out=$(lake comparator 2>&1) ;;
    check)   lake build Challenge >/dev/null 2>&1; out=$(lake env lean --run "$HERE/CheckChallenge.lean" 2>&1) ;;
  esac
  code=$?
  local verdict="ok"; [ "$code" = "$want" ] || { verdict="UNEXPECTED"; fails=$((fails+1)); }
  printf '%-18s %-8s exit %s (want %s) %-10s %s\n' "$name" "$tool" "$code" "$want" "$verdict" \
    "$(echo "$out" | grep -E 'error:|okay|FAILED' | head -2 | tr '\n' ' ')"
}
copy() { rm -rf "$W/$1"; cp -r "$B" "$W/$1"; }

copy honest
expect honest trusted 0
expect honest check 0

# Attacks in the solution (the agent's files).
for a in sorry axiom shadow-claim redefine-code; do
  copy $a; cp "$HERE/attacks/solution-$a.lean" "$W/$a/Solution.lean"
  expect $a trusted 1
done

# Editing a shared, human-audited file: passes by default, caught by the trusted export.
copy edit-shared-spec
cp "$HERE/attacks/solution-edit-shared-spec.lean" "$W/edit-shared-spec/Solution.lean"
patch -s "$W/edit-shared-spec/Toy/Spec.lean" < "$HERE/attacks/edit-shared-spec.diff"
expect edit-shared-spec default 0
expect edit-shared-spec trusted 1

# Sandbox probes: the proof is honest, so the verdict is accept; the probes must be blocked.
copy sandbox; cp "$HERE/attacks/solution-sandbox.lean" "$W/sandbox/Solution.lean"
expect sandbox default 0
(cd "$W/sandbox" && lake comparator 2>&1 | grep PROBE | sort -u)
[ -e "$HOME/PWNED_comparator_test" ] && { echo "SANDBOX ESCAPE: file written to real HOME"; fails=$((fails+1)); }

# Attacks in the code the challenge imports: the challenge itself is subverted, so the
# comparator (judging against that challenge) accepts; CheckChallenge rejects.
for a in code-macro code-shadow; do
  copy $a; patch -s "$W/$a/Toy/Categorize.lean" < "$HERE/attacks/$a.diff"
  cp "$HERE/attacks/solution-for-code-attacks.lean" "$W/$a/Solution.lean"
  expect $a default 0
  expect $a check 1
done
copy code-notation; patch -s "$W/code-notation/Toy/Categorize.lean" < "$HERE/attacks/code-notation.diff"
expect code-notation check 1

# The toy's existing code sabotages (checks 3 and 4): the logic is unchanged, so the
# comparator accepts; CheckChallenge rejects.
for a in code-rename-export code-swap-compiled; do
  copy $a; patch -s "$W/$a/Toy/Categorize.lean" < "$HERE/attacks/$a.diff"
  expect $a default 0
  expect $a check 1
done

echo "unexpected verdicts: $fails"
[ $fails = 0 ]
