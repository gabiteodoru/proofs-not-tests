#!/usr/bin/env bash
# Build the Lean code, compile it and the C shim, and link build/libtoy.so.
set -euo pipefail
cd "$(dirname "$0")"
P=$(lean --print-prefix)
mkdir -p build

# 1. Lean -> C (also checks every proof).
(cd lean && lake build)

# 2. C -> objects. The generated Lean C compiles with leanc (Lean's bundled
#    clang); the shim needs libc headers that leanc's sysroot lacks, so gcc.
leanc -c -fPIC -O2 lean/.lake/build/ir/Toy/Categorize.c -o build/Categorize.o
gcc -c -fPIC -O2 -Wall -I"$P/include" c/toy_shim.c -o build/toy_shim.o

# 3. Link. The stock static runtime (libleanrt.a) can't go into a shared
#    library (it uses local-exec TLS), so we link the toolchain's
#    libleanshared.so (about 230 MB on disk, about 21 MB resident in practice).
gcc -shared -o build/libtoy.so build/Categorize.o build/toy_shim.o \
  -L"$P/lib/lean" -lleanshared -Wl,-rpath,"$P/lib/lean"

# 4. C test driver for valgrind.
gcc -O1 -g -Wall c/test_shim.c -o build/test_shim -Lbuild -ltoy -Wl,-rpath,'$ORIGIN'

echo "built build/libtoy.so"
