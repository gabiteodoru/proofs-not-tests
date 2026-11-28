#!/usr/bin/env bash
# Evidence, not part of the audit. Runs the whole ./audit.sh on sabotaged copies
# of this folder and checks that each verdict is the expected one, and that a
# rejection comes from the step meant to catch it. The real repo is never touched.
#
# Usage: ./attacks.sh [--paranoid]    (the flag is passed on to audit.sh)
# About 2 minutes; about 5 with --paranoid. Needs bwrap (Linux).
#
# Each attack gets its own throwaway git repo holding a copy of this folder at
# the same path, so audit.sh runs exactly as it does here. Sabotage happens at
# one of two times:
#   - before the audit is recorded: the human "audited" a commit that already
#     contained it. Used for attacks in the implementation, which is frozen but not read,
#     so the file check can't help and CheckChallenge.lean must catch them.
#   - after the audit is recorded: an agent's later commit. Used for attacks in
#     the solution (caught by the comparator) and edits to audited files
#     (caught by the file check).
# If a sabotage no longer applies (say, the implementation changed), it's reported as
# such, not skipped.
set -uo pipefail

case "${1:-}" in
  ""|--paranoid) FLAG="${1:-}" ;;
  *) echo "usage: $0 [--paranoid]"; exit 2 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
A="$HERE/attacks"
REL="$(git -C "$HERE" rev-parse --show-prefix)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
failed=0

commit() {
  git -C "$1" add -A
  git -C "$1" -c user.name=attacks -c user.email=attacks@invalid commit -q --allow-empty -m "$2"
}

# attack NAME WANT MARKER BEFORE AFTER
#   BEFORE and AFTER are shell commands run in the copy of this folder, before
#   and after the audit is recorded. WANT is pass or fail; the output must
#   contain MARKER, evidence that the intended step decided the verdict.
attack() {
  local name=$1 want=$2 marker=$3 before=$4 after=$5
  local R="$W/$name" T="$W/$name/$REL" out got
  mkdir -p "$T"
  tar -C "$HERE" --exclude=./build --exclude=./lean/.lake --exclude=__pycache__ -cf - . | tar -C "$T" -xf -
  git -C "$R" init -q
  if ! (cd "$T" && eval "$before") || ! { commit "$R" "audited state" && git -C "$R" rev-parse HEAD > "$T/AUDITED_COMMIT" && commit "$R" "record the audit"; } || ! (cd "$T" && eval "$after"); then
    echo "BROKEN  $name: the sabotage didn't apply"; failed=1; return
  fi
  commit "$R" "after the audit"
  if out="$("$T/audit.sh" $FLAG 2>&1)"; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ] && grep -qF -- "$marker" <<<"$out"; then
    echo "ok      $name: $want ($marker)"
  else
    echo "MISSED  $name: got $got, want $want with '$marker'"; failed=1
    sed 's/^/        | /' <<<"$out" | tail -15
  fi
  LAST_OUT=$out
}

sol()   { echo "cp '$A/solution-$1.lean' lean/Solution.lean"; }
patch_impl() { echo "patch -s lean/Toy/Categorize.lean < '$A/$1.diff'"; }

attack baseline            pass "AUDIT PASSED" true true

# The agent's solution (after the audit): the comparator rejects.
attack solution-sorry         fail "sorryAx"                   true "$(sol sorry)"
attack solution-axiom         fail "Illegal axiom detected: 'cheat'" true "$(sol axiom)"
attack solution-easier-claim  fail "theorem statement do not match: 'Toy.c1'" true "$(sol easier-claim)"
attack solution-shadow-claim  fail "theorem statement do not match: 'Toy.c1'" true "$(sol shadow-claim)"
attack solution-redefine-code fail "Const does not match between challenge and target 'Toy.categorizeFFI'" true "$(sol redefine-code)"

# Build-time code in the solution: the verdict is pass, but the probes must be blocked.
rm -f "$HOME/PWNED_comparator_test"
attack sandbox pass "AUDIT PASSED" true "cat '$A/sandbox-probes.lean' >> lean/Solution.lean"
for p in "write project source" "read home" "network"; do
  grep -qF "PROBE $p: blocked" <<<"${LAST_OUT:-}" && echo "ok      sandbox: $p blocked" \
    || { echo "MISSED  sandbox: '$p' not shown as blocked"; failed=1; }
done
[ -e "$HOME/PWNED_comparator_test" ] && { echo "MISSED  sandbox: a file was written to the real home directory"; failed=1; }

# Edits to an audited file after the audit: the file check rejects.
attack edit-spec fail "AUDIT FAILED: audited files changed" true \
  "patch -s lean/Toy/Spec.lean < '$A/edit-spec.diff' && $(sol edit-spec)"

# An implementation that was bad when "audited" (it isn't read): CheckChallenge.lean rejects,
# although the comparator, judging the subverted challenge, accepts.
attack implementation-macro         fail "FAILED statement of Toy.c1"   "$(patch_impl implementation-macro)"    "$(sol for-implementation-attacks)"
attack implementation-shadow        fail "FAILED statement of Toy.c1"   "$(patch_impl implementation-shadow)"   "$(sol for-implementation-attacks)"
attack implementation-notation      fail "FAILED implementation declares no syntax"   "$(patch_impl implementation-notation)" true
attack implementation-rename-export fail "FAILED export name"           "$(patch_impl implementation-rename-export)" true
attack implementation-swap-compiled fail "FAILED no swapped compiled code"  "$(patch_impl implementation-swap-compiled)" true

[ "$failed" = 0 ] && echo "ALL ATTACKS GAVE THE EXPECTED VERDICT" || echo "SOME ATTACKS DID NOT"
exit $failed
