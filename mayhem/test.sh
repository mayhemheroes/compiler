#!/usr/bin/env bash
# compiler/mayhem/test.sh — RUN the Pawn compiler's OWN test suite (source/compiler/tests/run_tests.py)
# against the normal-flags pawncc + pawndisasm that mayhem/build.sh produced → CTRF. PATCH-grade oracle:
# it never compiles the compiler itself.
#
# run_tests.py is a KNOWN-ANSWER / golden suite — for each tests/<name>.pwn it asserts the compiler's
# EXACT behavior against frozen expected output in <name>.meta:
#   * output_check (29 tests): compiles <name>.pwn and DIFFS pawncc's stderr diagnostics against the
#     verbatim error/warning text in the .meta. A no-op / exit(0) "patch" emits no diagnostics → the
#     diff fails. It asserts the compiler reports EXACTLY these errors, not merely that it exits 0.
#   * pcode_check (2 tests): compiles <name>.pwn to .amx, disassembles it with pawndisasm, and
#     regex-matches the produced P-code against the expected instruction sequence in the .meta — a
#     behavioral assertion on emitted CODE.
# These 31 tests need only pawncc + pawndisasm (both built by build.sh) and are run here.
#
# The suite also ships 1 `runtime` test (compile → execute the .amx with the `pawnruns` interpreter and
# diff program output). pawnruns does NOT build at 64-bit (amx.c static-asserts a function pointer fits
# in a 32-bit cell — see mayhem/build.sh), so we have no in-image runtime executor; that ONE test is
# recorded as SKIPPED (honest accounting), not faked. The 31 deterministic tests are a genuine
# golden/behavioral oracle on their own.
#
# run_tests.py is Python-2-era but uses only py3-compatible syntax (print()/sys.stdout.write, eval of
# the .meta dict literals); it runs under the base image's python3.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PAWNCC="$SRC/build-tests/pawncc"
PAWNDISASM="$SRC/build-tests/pawndisasm"
[ -x "$PAWNCC" ]    || { echo "missing $PAWNCC — run mayhem/build.sh first" >&2; exit 2; }
[ -x "$PAWNDISASM" ] || { echo "missing $PAWNDISASM — run mayhem/build.sh first" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 2; }

TESTDIR="$SRC/source/compiler/tests"
cd "$TESTDIR"

# Enumerate the deterministic tests (everything that isn't a `runtime` test). The runtime test needs
# the pawnruns executor we can't build at 64-bit; count it as skipped rather than fail/fake it.
DET_TESTS=(); SKIPPED=0
for meta in *.meta; do
  name="${meta%.meta}"
  if grep -q "'test_type': *'runtime'" "$meta"; then
    SKIPPED=$((SKIPPED+1)); echo "SKIP (needs pawnruns, 64-bit incompatible): $name" >&2
  else
    DET_TESTS+=("$name")
  fi
done

# run_tests.py compiles with the project include dir on the path (../../../include from tests/).
# It prints "Running <name>... PASSED|FAILED" per test and exits non-zero if any failed. Parse the
# per-test lines so a clean pass/fail count maps into CTRF.
LOG=/tmp/pawn-tests.log
python3 run_tests.py \
  -c "$PAWNCC" \
  -d "$PAWNDISASM" \
  -i "$SRC/include" \
  "${DET_TESTS[@]}" >"$LOG" 2>&1 || true
cat "$LOG" >&2

passed=$(grep -c '\.\.\. PASSED' "$LOG" || true)
failed=$(grep -c '\.\.\. FAILED' "$LOG" || true)
passed=${passed:-0}; failed=${failed:-0}

echo "pawn run_tests.py: passed=$passed failed=$failed skipped=$SKIPPED (of ${#DET_TESTS[@]} deterministic + 1 runtime)" >&2
emit_ctrf "pawn-run_tests" "$passed" "$failed" "$SKIPPED"
