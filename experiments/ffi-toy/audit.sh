#!/usr/bin/env bash
# Human-audited. The proof audit for the toy, on committed files only.
#
# Usage: ./audit.sh [--paranoid]
#   --paranoid  also re-check the proofs with five independent kernels (about
#               35 s instead of about 12 s). Use it for a real audit.
#
# Steps (why each exists: notes/audit-integrity.md, last section):
#   1. refuse uncommitted changes, so "passed" is about one commit;
#   2. file check: the audited files are unchanged since the commit recorded
#      in AUDITED_COMMIT;
#   3. clean clone of HEAD, so no build output from the working tree is used;
#   4. lake comparator: Solution.lean proves Challenge.lean's theorems, using
#      only the axioms permitted in comparator.json (inside a bwrap sandbox);
#   5. CheckChallenge.lean: the checks the comparator doesn't do.
set -euo pipefail

case "${1:-}" in
  "")         PARANOID=""; MODE="kernel only" ;;
  --paranoid) PARANOID="--paranoid"; MODE="paranoid: kernel plus five independent checkers" ;;
  *)          echo "usage: $0 [--paranoid]"; exit 2 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
REL="$(git -C "$HERE" rev-parse --show-prefix)"     # this folder, relative to the repo root

# The human-audited files, relative to this folder. The implementation
# (Categorize.lean) is here because it's frozen, not because it's read. Proof files are not.
AUDITED_FILES=(
  SPEC.md
  lean/Toy/Spec.lean
  lean/Toy/Categorize.lean
  lean/Toy.lean
  lean/Challenge.lean
  lean/comparator.json
  lean/lakefile.toml
  lean/lake-manifest.json
  lean/lean-toolchain
  CheckChallenge.lean
  build.sh
  audit.sh
  expenses_lean.py        # the Python glue: its type checks are read (SPEC.md, "Boundary")
  c/toy_shim.c            # the C shim: read (README, "How to audit", part 3)
)

# 1. Committed files only.
if [ -n "$(git -C "$HERE" status --porcelain -- .)" ]; then
  echo "AUDIT NOT RUN: uncommitted changes in ${REL:-.}"; exit 1
fi
HEAD_COMMIT="$(git -C "$HERE" rev-parse HEAD)"
echo "commit:         $HEAD_COMMIT"

# 2. File check. AUDITED_COMMIT's first line is the commit whose audited files a
#    human read; only the human updates it, and that update is the (re-)audit.
AUDITED="$(head -n 1 "$HERE/AUDITED_COMMIT" | tr -d '[:space:]')"
if ! git -C "$HERE" rev-parse --verify --quiet "$AUDITED^{commit}" >/dev/null; then
  echo "AUDIT FAILED: AUDITED_COMMIT ('$AUDITED') is not a commit in this repository"; exit 1
fi
echo "audited commit: $AUDITED"
for f in "${AUDITED_FILES[@]}"; do
  [ -f "$HERE/$f" ] || { echo "AUDIT FAILED: audited file $f is missing"; exit 1; }
done
if ! git -C "$HERE" diff --exit-code --stat "$AUDITED" "$HEAD_COMMIT" -- "${AUDITED_FILES[@]}"; then
  echo "AUDIT FAILED: audited files changed since the audited commit (listed above); re-audit them"
  exit 1
fi
echo "ok     audited files unchanged since the audited commit"

# 3. Clean clone of HEAD.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git clone -q --no-checkout "$TOP" "$WORK/repo"
git -C "$WORK/repo" -c advice.detachedHead=false checkout -q "$HEAD_COMMIT"
cd "$WORK/repo/${REL}lean"

# 4. The comparator.
echo "== lake comparator $PARANOID"
lake comparator $PARANOID

# 5. Checks on the challenge, loaded as data.
echo "== CheckChallenge.lean"
lake build --quiet Challenge
lake env lean --run ../CheckChallenge.lean

echo "AUDIT PASSED ($MODE)"
