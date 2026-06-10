/*
 * asan_options.c — disable LeakSanitizer under Mayhem's ptrace-based coverage tracer.
 *
 * LSan (enabled by default with -fsanitize=address) ptrace-attaches to its own threads
 * at process exit to scan for leaks. Mayhem's coverage collector already holds the ptrace
 * slot (Linux allows only one tracer per process), so LSan aborts with "does not work
 * under ptrace" → process exits 1 before any edges are recorded → 0-edge "Run Failed" /
 * has_critical_errors.
 *
 * Fix: bake detect_leaks=0 into the binary via the weak __asan_default_options hook.
 * The hook fires at ASan init, before any runtime ASAN_OPTIONS parsing or tracer attach,
 * so it reliably disables LSan while leaving full ASan + UBSan detection active.
 * Leak scanning is not useful for fuzzing (leaks are not crashes; short iterations leak by
 * design) — the high-value detectors (out-of-bounds, use-after-free via ASan, undefined
 * behavior via UBSan) remain fully ON and HALTING.
 *
 * Reference: README.md FAQ "A target passes locally but reads 0 edges / Run Failed" —
 * cause 1 (LeakSanitizer aborts under ptrace).
 */
__attribute__((weak)) const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
