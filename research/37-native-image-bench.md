# 37 — Native images and warmed-up JVMs (2026-10-30)

Closes "measure this once 0.65 ships" (research/08) and "benchmark against native-image builds" (research/02).
Figures here are from the first run; the current ones are in `docs/performance.md`, from a full rerun within ~10% of these.

## Setup

Ryzen 7 9700X, 16 CPUs, shared box (load average about 3-6 during the run), Java 21.0.12, hyperfine 1.20.0, ktrs 0.5.3
dist binaries. `tools/bench/public.sh --ktlint 2.0.0-ALPHA-4`, plus `tools/bench/jvm-warm.sh 30 5`. Not comparable
with research/23's Xeon figures.

## ktfmt 0.65 native image

Reading:
- It removes startup: 374 ms to 7 ms on one file. ktrs's lead there falls to 2-4x, and both are imperceptible.
- It does not remove per-file cost. No JIT and Serial GC: at the corpus it ties the jar (4.65 vs 4.72 s) using 24 s
  of CPU against 63 s. ktrs stays 16x ahead from okhttp upward.
- On 1 core it beats the jar 2.8x, since the JVM's JIT competes with the work there.
- Output matches the jar on okhttp (562 files changed, no differences). Corpus not compared.
- Binary 56 MB, not the 13-16 MB research/08 expected.

## ktlint 2.0.0-ALPHA-4 native image: crashes

`ktlint_linux-x86-64` prints its version but fails on lint, `--stdin` and `-F`, even on a trivial file:
`ExceptionInInitializerError`, caused by `Could not find 'theUnsafe' field in the Unsafe class`
(`ReflectionUtil.<clinit>`, a reflection-config gap; research/13 saw the same). macOS and Windows binaries untested.
A search of the ktlint issues found no report.

The exit code is 1, the same as "lint errors found", so hyperfine `--ignore-failure` timed the crash as a 2.5 ms run
and the summary's exit-code warning did not fire. `public.sh` now probes the output first and drops a crashing
binary. Don't trust a sub-10 ms row without checking it did the work.

## Warmed-up JVM

`JvmWarm.java` loops the CLI's `main()` in one JVM. ktfmt format okhttp: 1.91 s first iteration, 284 ms settled by
about iteration 8. ktlint lint okhttp: 4.34 s first, 3.01 s settled by iteration 3, with the same 14 MB of output
each time, so later iterations do the full work.

So cold start and JIT account for most of ktfmt's gap (25x cold, 4x warm) but little of ktlint's (37x cold, 25x
warm). Warm ktfmt in a long-lived process is the competitor worth watching, as the Spotless warm-daemon row shows.

## Gotchas

- hyperfine's RSS is a high-water mark across a call (`getrusage(RUSAGE_CHILDREN)`), so anything after the jar reads
  as the jar. `public_summary.py` blanks those rows; use `/usr/bin/time` for them. Native, okhttp 364 MB, corpus
  1,074 MB, okhttp 1 core 189 MB.
- hyperfine 1.19 records no RSS; the workflow pins 1.20.
- `Runtime.halt` also goes through `SecurityManager.checkExit`, hence `looping` in `JvmWarm.java`.
- The old Spotless table (~52 s fresh for ktfmt 0.64) had no script behind it and doesn't reproduce: `spotless.py` gives
  3.2 s for ktfmt 0.65 on this box. The old machine and setup are unknown, so don't read that as a ktfmt speedup.
