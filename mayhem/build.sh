#!/usr/bin/env bash
# compiler/mayhem/build.sh — build the Pawn compiler driver (pawncc) as the fuzz target, plus a
# clean normal-flags build of pawncc + pawndisasm for the project's OWN golden test suite (mayhem/test.sh).
#
# This is the upstream `pawn-lang/compiler` (the Pawn language). Its sources live under
# source/compiler/ (CMake project `pawnc`). The driver `pawncc` reads a .p/.pawn SOURCE FILE and
# compiles it to an .amx P-code module (lexer + preprocessor + parser + semantic analysis + codegen).
# The Mayhem target is FILE-INPUT (CLI): `pawncc @@` runs the whole compiler on the fuzz bytes as a
# Pawn source file. There is NO libFuzzer harness — the compiler binary IS the natural fuzz surface
# (a single input file crashes naturally), exactly like the lacc/fcc/my_basic file-input template. So
# no *-standalone reproducer either: the file-input target already reproduces on one input file.
#
# build.sh produces:
#   (1) /mayhem/pawncc           — SANITIZED fuzz target (ASan+UBSan halting, by default)
#   (2) test-oracle binaries     — /mayhem/build-tests/pawncc + /mayhem/build-tests/pawndisasm,
#                                  NORMAL flags (no sanitizers), used by mayhem/test.sh's golden suite.
#
# 64-bit native build. The OLD mayhemheroes integration built -m32; we build native 64-bit so the
# fuzzed code is instrumented by clang's stock ASan/UBSan runtimes (the base ships x86_64 runtimes,
# not the i386 ones). pawncc + pawndisasm build cleanly at 64-bit. The runtime executor `pawnruns`
# does NOT build at 64-bit (amx.c has assert_static(sizeof(funcptr) <= sizeof(cell)); cell is 32-bit,
# so an 8-byte function pointer fails the static assert) — it is only needed by the single `runtime`
# test, which mayhem/test.sh records as SKIPPED. The 31 deterministic tests (output_check + pcode_check)
# need only pawncc + pawndisasm and form a real behavioral/golden oracle (see mayhem/test.sh).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the base ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit
# empty value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the compiler's natural
# crash). pawncc links only pthread (added by the CMakeLists on UNIX) — present without the sanitizer
# runtime — so the empty-sanitizer build links cleanly.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# The compiler is old C with a few clang-noisy constructs (unknown GCC attributes, etc.) but compiles
# and runs cleanly under ASan+UBSan: a valid Pawn program runs to exit 0 with no sanitizer output, and
# malformed input crashes naturally (assert/SIGABRT, ASan reports). We smoke-tested representative
# valid programs and found NO ubiquitous benign-UB flood, so NO -fno-sanitize relaxation is needed —
# ASan + full UBSan stay ON and HALTING, so every real memory/UB defect in the compiler crashes the
# fuzzer. (If a future upstream change introduces a benign-UB flood on every input, relax ONLY that one
# check here under `grep -q undefined`, per PORTING.md — keeping ASan + the rest of UBSan halting.)

# ---------------------------------------------------------------------------
# (1) FUZZ build — pawncc compiled WITH $SANITIZER_FLAGS so the fuzzed code (the whole compiler:
#     preprocessor, lexer, parser, semantic analysis, codegen) is instrumented. The file-input Mayhem
#     target lands at /mayhem/pawncc. Built via the upstream CMake project under source/compiler.
#
# asan_options.o: bake detect_leaks=0 into the binary to suppress LSan under Mayhem's ptrace-based
# coverage tracer. LSan ptrace-attaches its own threads at exit to scan leaks; Mayhem already holds
# the ptrace slot → LSan aborts → 0-edge "Run Failed" / has_critical_errors. Compiled and injected
# via CMAKE_EXE_LINKER_FLAGS so it lands in the pawncc link line (not the shared libpawnc.so link).
# Full ASan + UBSan detection remains active; only leak scanning is disabled (see asan_options.c).
# ---------------------------------------------------------------------------
FUZZ_BUILD="$SRC/build"
rm -rf "$FUZZ_BUILD"; mkdir -p "$FUZZ_BUILD"
# Compile the LSan-disable stub before cmake configure so the object exists for the linker.
$CC $DEBUG_FLAGS -c "$SRC/mayhem/asan_options.c" -o /tmp/asan_options.o
cmake -S "$SRC/source/compiler" -B "$FUZZ_BUILD" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="/tmp/asan_options.o" \
  -DBUILD_TESTING=OFF >/dev/null
cmake --build "$FUZZ_BUILD" --target pawncc -j "$MAYHEM_JOBS"
cp -f "$FUZZ_BUILD/pawncc" /mayhem/pawncc
# pawncc links the shared libpawnc.so it builds alongside; keep it next to the target so the
# fuzz binary resolves it at runtime (CMake bakes an rpath, but copy defensively).
cp -f "$FUZZ_BUILD"/libpawnc.so* /mayhem/ 2>/dev/null || true

# ---------------------------------------------------------------------------
# (2) TEST-ORACLE build — pawncc + pawndisasm with the project's NORMAL flags (no sanitizer), for
#     mayhem/test.sh's golden suite. A clean, independent build so the oracle reflects real shipped
#     behavior and never false-fails on sanitizer noise; test.sh only RUNS these (it never compiles).
#     BUILD_TESTING=ON wires the tests/ subdir; we build pawncc + pawndisasm (pawnruns is 64-bit
#     incompatible, see header — its single runtime test is reported skipped).
# ---------------------------------------------------------------------------
TEST_BUILD="$SRC/build-tests"
rm -rf "$TEST_BUILD"; mkdir -p "$TEST_BUILD"
cmake -S "$SRC/source/compiler" -B "$TEST_BUILD" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_C_FLAGS="$DEBUG_FLAGS" \
  -DBUILD_TESTING=ON >/dev/null
cmake --build "$TEST_BUILD" --target pawncc pawndisasm -j "$MAYHEM_JOBS"

echo "build.sh: built /mayhem/pawncc (sanitized fuzz target) and $TEST_BUILD/{pawncc,pawndisasm} (test oracle)"
ls -l /mayhem/pawncc "$TEST_BUILD/pawncc" "$TEST_BUILD/pawndisasm"
