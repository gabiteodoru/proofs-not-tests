#!/usr/bin/env bash
# Human-audited. Runs every check in lean/Toy/Audit.lean, on committed code only.
set -euo pipefail
cd "$(dirname "$0")/lean"

# The checks must run on exactly what was read and committed.
if [ -n "$(git status --porcelain -- .)" ]; then
  echo "AUDIT NOT RUN: uncommitted changes under lean/"; exit 1
fi
echo "commit: $(git rev-parse HEAD)"

lake build Toy.Audit                    # runs the checks in Audit.lean
lake env leanchecker Toy                # re-checks every Toy.* definition in Lean's kernel
echo "AUDIT PASSED"
