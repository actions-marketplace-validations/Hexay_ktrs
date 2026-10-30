# Performance

All figures: ktrs 0.5.3, Ryzen 7 9700X, 16 CPUs, Linux, JDK 21, 2026-10-30. The machine is shared with other
work. Absolute times are only comparable within this page.

## How it is measured

- **Fresh process, JVM warm-up included.** Each timed run starts a new process, as a CLI, hook or CI step does. Jar
  times include JVM startup, class loading and a cold JIT.
- **The discarded run is not JVM warm-up.** hyperfine runs each command once untimed first. That warms the OS file
  cache and nothing else, because the JVM exits.
- **Statistic.** Median wall time of 5 runs. Commands run one tool after another, not interleaved, so slow drift
  on the machine lands on one tool.
- **Same work.** Same flags and files for each tool. ktfmt rejects 2 of the 6,123 files, Exposed's `{{packageName}}`
  code-generator templates, and ktrs rejects them with the same error. The ktfmt native image's output was compared
  with the jar's on okhttp: no differences.
- **Format scenarios** copy the tree once, so the discarded run formats it and the timed runs re-format already
  formatted files. **Autocorrect** gets a fresh copy before every run, untimed.
- **1 core.** Pinned to one CPU from launch. The JVM sizes its GC and JIT threads for one CPU, as in a 1-CPU
  container, and its JIT competes with the work.
- **Under 5 ms.** hyperfine's shell-startup correction is the main error at this scale, so these rows are bounds and
  their ratios are approximate.
- **Memory.** Max RSS. hyperfine's value is a high-water mark across a call, so a command run after the jar inherits
  the jar's. Native image figures come from `/usr/bin/time` instead.
- **Inputs.** okhttp plus 6 more projects (kotlinx.coroutines, nowinandroid, ktlint, ktfmt, Exposed, ktor), 6,123
  files and 31 MB in total, at the commits in [`tools/bench/REVISIONS`](../tools/bench/REVISIONS). Jars and native
  images are checked against pinned SHA-256 values.

## Formatting: ktfmt 0.65

"GraalVM" is the native image ktfmt publishes with each release, built with GraalVM CE 25.2.4, so without PGO. "JVM" is
the release jar on a stock JDK.

| Scenario | ktrs | ktfmt (GraalVM) | ktfmt (JVM) | ktrs vs GraalVM | ktrs vs JVM |
|---|--:|--:|--:|--:|--:|
| Editor: one 8 KB file on stdin | <5 ms | 7.1 ms | 376 ms | **~5x** | **>70x** |
| Pre-commit: 10 changed files | <5 ms | 6.4 ms | 365 ms | **~2x** | **>70x** |
| CI check on okhttp (617 files) | 90 ms | 1.41 s | 2.01 s | **16x** | **22x** |
| Format okhttp in place | 73 ms | 1.13 s | 1.74 s | **16x** | **24x** |
| Format okhttp in place, 1 core | 250 ms | 2.48 s | 6.81 s | **10x** | **27x** |
| Format 7 projects (6,123 files) | 298 ms | 4.68 s | 4.70 s | **16x** | **16x** |

| Max RSS | ktrs | ktfmt (GraalVM) | ktfmt (JVM) |
|---|--:|--:|--:|
| One 8 KB file on stdin | 18 MB | 36 MB | 154 MB |
| Format okhttp in place | 514 MB | 356 MB | 1,145 MB |
| Format okhttp in place, 1 core | 98 MB | 186 MB | 269 MB |
| Format 7 projects | 611 MB | 936 MB | 1,709 MB |

The native image removes JVM startup but not per-file cost. It has no JIT, so its lead over the jar shrinks as the
run grows and is gone at 6,123 files. ktrs uses more memory than the native image on okhttp with all cores.

## Linting: ktlint

ktrs's default mode against the 2.0.0-ALPHA-4 jar:

| Scenario | ktrs | ktlint (JVM) | ktrs speedup |
|---|--:|--:|--:|
| Editor: one 8 KB file on stdin | <5 ms | 507 ms | **>100x** |
| Lint one file | <5 ms | 402 ms | **>80x** |
| Lint okhttp (617 files) | 119 ms | 4.41 s | **37x** |
| Lint okhttp, 1 core | 691 ms · 50 MB | 19.29 s · 292 MB | **28x** |
| Lint 7 projects (6,123 files) | 640 ms · 368 MB | 19.65 s · 736 MB | **31x** |
| Autocorrect okhttp (`-F`) | 219 ms | 42.73 s | **195x** |
| Autocorrect 7 projects (`-F`) | 1.38 s | 120.16 s | **87x** |

ktrs's 1.8 mode (`--ktlint-version=1.8`) against the 1.8.0 jar. It visits the tree once per rule, as 1.8 does, so it
is about 2x slower than the default mode, while the 1.8.0 jar is faster than the 2.0 jar:

| Scenario | ktrs, 1.8 mode | ktlint 1.8.0 (JVM) | ktrs speedup |
|---|--:|--:|--:|
| Lint okhttp (617 files) | 220 ms | 3.25 s | **15x** |
| Lint 7 projects (6,123 files) | 1.29 s | 13.05 s | **10x** |

**No GraalVM column.** ktlint's 2.0.0-ALPHA-4 `ktlint_linux-x86-64` binary crashes on every lint or format
(`Could not find 'theUnsafe' field in the Unsafe class`). `public.sh` checks for this and adds the column once a pinned
binary works. The macOS and Windows binaries were not tested. This is the published build, not a limit of GraalVM:
others report working ktlint native images.

## GraalVM with PGO: not measured

Profile-guided optimization should make a native image faster and smaller than the figures above, and needs Oracle GraalVM.
We tried to build both tools with it on this machine, under an 8 GB limit per job, and got no working binary
([research/37](../research/37-native-image-bench.md)). A community experiment reports 15-30% better performance and a
binary about half the size; we have not reproduced that. Treat the GraalVM column as the published build, not GraalVM's
best case.

## Binary size

| Tool | ktrs | GraalVM, published | Jar |
|---|--:|--:|--:|
| ktfmt | 1.6 MB | 56.5 MB | 71.5 MB, plus a JRE |
| ktlint | 4.3 MB | 62.3 MB (crashes) | 75.4 MB, plus a JRE |

The `ktrs` binary, with both tools and the language server, is 6.5 MB.

## Warmed-up JVM

The jars' best case. `tools/bench/jvm-warm.sh` calls each CLI's `main()` 30 times in one JVM and takes the median of
the last 5, so there is no startup and the JIT is trained. No command-line user gets this speed; a long-lived process
can approach it.

| okhttp (617 files) | ktrs | JVM, fresh process | JVM, warmed up | ktrs vs warmed up |
|---|--:|--:|--:|--:|
| Format in place | 73 ms | 1.74 s | 276 ms | **4x** |
| Lint | 119 ms | 4.41 s | 2.96 s | **25x** |

## Spotless

`spotlessApply` on okhttp's 573 `.kt` files with Spotless 8.10.4, `kotlinlang` style. Output is identical. The share is
the total minus a baseline Spotless run that only trims whitespace (2.22 s fresh, 0.34 s warm).

| Gradle daemon | ktrs total | ktfmt 0.65 total | ktrs share | ktfmt share |
|---|--:|--:|--:|--:|
| Fresh, as in CI | 2.64 s | 5.43 s | 0.42 s | 3.21 s |
| Warm, repeated runs | 0.76 s | 2.07 s | 0.41 s | 1.73 s |

## Reproduce

```sh
cargo build --profile dist --bins
tools/bench/public.sh             # every CLI scenario (about 45 min here); --only quick for a subset, --list for ids
tools/bench/jvm-warm.sh           # warmed-up JVM, after public.sh has fetched the jars and corpus
tools/bench/spotless.py           # Spotless, also after public.sh
```

Needs Linux or macOS, hyperfine 1.20+, Java 21 and python3. Not scripted: the 1.8-mode rows (hyperfine on `ktlint
--relative --ktlint-version=1.8` from the same directories) and the native image RSS (`/usr/bin/time -f %M`).

The `bench` workflow runs `public.sh` on a GitHub runner for each release tag or on demand. Design notes:
[research/23](../research/23-public-bench.md), [research/37](../research/37-native-image-bench.md).
