<div align="center">

# ktrs

**Kotlin formatting and linting in Rust, without starting a JVM.**

[![CI](https://github.com/Hexay/ktrs/actions/workflows/ci.yml/badge.svg)](https://github.com/Hexay/ktrs/actions/workflows/ci.yml)
[![crates.io](https://img.shields.io/crates/v/ktrs.svg)](https://crates.io/crates/ktrs)
[![License](https://img.shields.io/badge/license-MIT%20%2F%20Apache--2.0-blue.svg)](#license)
[![Playground](https://img.shields.io/badge/try%20it-playground-7f52ff.svg)](https://hexay.github.io/ktrs/)

<img src="assets/benchmark.svg" alt="Format okhttp: ktrs 0.07 s, ktfmt GraalVM native image 1.13 s, ktfmt jar 1.74 s. Lint okhttp: ktrs 0.12 s, ktlint jar 4.41 s." width="720">

</div>

ktrs is a native replacement for [ktfmt](https://github.com/facebook/ktfmt) and
[ktlint](https://github.com/pinterest/ktlint). It produces the same output and ships as small binaries
with no runtime. Try the formatter in the **[playground](https://hexay.github.io/ktrs/)**, which runs it
as WebAssembly.

- ⚡ **Fast.** 10-200x faster than the JVM tools and 2-16x faster than ktfmt's published GraalVM native
  image ([Performance](#performance)).
- 🎯 **Identical output.** Byte-identical to ktfmt 0.65 on 6,121 of 6,123 real-world files (both
  tools reject the other two). Lint violations and `--format` output match ktlint 2.0 in all three
  code styles, and ktlint 1.8 in a compatibility mode ([How we test](#how-we-test)).
- 🔌 **Drop-in.** The `ktfmt` and `ktlint` binaries accept the originals' flags, messages and exit
  codes, so existing scripts, hooks and CI keep working.
- 🧩 **Fits your setup.** [GitHub Actions](#github-actions), [pre-commit](#pre-commit),
  [editors](docs/editors.md), [Gradle, Maven and Spotless](docs/build-tools.md),
  [Bazel, reviewdog and Danger](docs/ci-integrations.md).
- 🌳 **Built on a faithful parser.** The lossless Kotlin parser's tree matches the compiler's PSI node
  for node, and [you can use it as a library](#use-the-parser-as-a-library).

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/Hexay/ktrs/master/install.sh | sh   # prebuilt binaries
cargo binstall ktrs                                                               # prebuilt, via cargo-binstall
cargo install ktrs                                                                # from crates.io
brew tap hexay/ktrs https://github.com/Hexay/ktrs && brew install hexay/ktrs/ktrs  # Homebrew
scoop bucket add ktrs https://github.com/Hexay/ktrs && scoop install ktrs/ktrs     # Scoop (Windows)
npm install --save-dev @ktrs/cli                                                  # npm (npx ktlint, npx ktfmt)
docker run --rm -v "$PWD:/src" ghcr.io/hexay/ktrs ktlint "**/*.kt"                 # Docker (linux amd64/arm64)
```

One install puts three binaries on your PATH: `ktrs`, `ktfmt` and `ktlint`. On Windows, the
install script also works under Git Bash, or download a zip from
[Releases](https://github.com/Hexay/ktrs/releases). The Docker image takes the binary name as its first argument,
works in `/src`, and has no Java, so `ktlint -R` with a rule set other than compose-rules doesn't run there; on
Linux, add `--user "$(id -u):$(id -g)"` to keep fixed files owned by you.

## Usage

```sh
ktrs fmt                              # format every .kt/.kts under the current directory
ktrs fmt --style kotlinlang src/      # styles: meta (default), google, kotlinlang
ktrs fmt --check                      # CI: list files that would change, exit 1 if any
ktrs fmt --changed-since main         # only files changed since the merge base with main
ktrs fmt - < Foo.kt                   # stdin to stdout, for editors

ktrs lint                             # check every .kt/.kts under the current directory
ktrs lint --format src/               # autocorrect what can be fixed, report the rest
ktrs lint --changed-since main        # only files changed since the merge base with main
ktrs lint --reporter json - < Foo.kt  # reporters: plain, json, checkstyle, sarif, html, ...
```

### Drop-in for ktfmt and ktlint

The `ktfmt` and `ktlint` binaries accept the original command lines exactly, so anything that runs
the jars can run them instead:

```sh
ktfmt --kotlinlang-style --set-exit-if-changed src/
ktlint --relative "src/**/*.kt" "!src/**/generated/**"
```

`ktfmt` formats like ktfmt 0.65. `ktlint` behaves like 2.0.0-ALPHA-4 with all 105 standard rules; for 1.8.0, pass
`--ktlint-version=1.8` or set it in `.editorconfig`. [compose-rules](https://github.com/mrmans0n/compose-rules) runs
natively, and any other `-R` rule set runs through the real ktlint jar at JVM speed. Details and limits:
[docs/compatibility.md](docs/compatibility.md).

## Performance

Each tool runs from the command line with the same flags and files. Times are the median wall time of 5
runs of a **fresh process**, on one Linux machine (Ryzen 7 9700X, 16 CPUs, JDK 21).

**JVM warm-up is included.** Every run starts a new JVM, so JVM times include startup, class loading and
a cold JIT, which is what a CLI, hook or CI step pays. The last table shows the JVM fully warmed up.

| Scenario | ktrs | ktfmt 0.65 (GraalVM) | ktfmt 0.65 (JVM) | ktrs vs GraalVM | ktrs vs JVM |
|---|--:|--:|--:|--:|--:|
| Editor: one 8 KB file on stdin | <5 ms | 7.1 ms | 376 ms | **~5x** | **>70x** |
| Pre-commit: 10 changed files | <5 ms | 6.4 ms | 365 ms | **~2x** | **>70x** |
| Format okhttp (617 files) | 73 ms | 1.13 s | 1.74 s | **16x** | **24x** |
| Format okhttp, 1 core | 250 ms | 2.48 s | 6.81 s | **10x** | **27x** |
| Format 7 projects (6,123 files) | 298 ms | 4.68 s | 4.70 s | **16x** | **16x** |

GraalVM here is the native image ktfmt publishes, which has no PGO. A PGO build should do better, and
[we couldn't build one to measure](docs/performance.md#graalvm-with-pgo-not-measured).

| Scenario | ktrs | ktlint (JVM) | ktrs speedup |
|---|--:|--:|--:|
| 2.0: lint one file | <5 ms | 402 ms | **>80x** |
| 2.0: lint okhttp | 119 ms | 4.41 s | **37x** |
| 2.0: lint 7 projects | 640 ms | 19.65 s | **31x** |
| 2.0: autocorrect okhttp (`-F`) | 219 ms | 42.73 s | **195x** |
| 1.8 mode: lint okhttp | 220 ms | 3.25 s | **15x** |
| 1.8 mode: lint 7 projects | 1.29 s | 13.05 s | **10x** |

ktlint has no GraalVM column because its published 2.0.0-ALPHA-4 Linux native image crashes on every lint or format.

| JVM warmed up, okhttp | ktrs | JVM, fresh process | JVM, warmed up | ktrs vs warmed up |
|---|--:|--:|--:|--:|
| Format (ktfmt) | 73 ms | 1.74 s | 276 ms | **4x** |
| Lint (ktlint 2.0) | 119 ms | 4.41 s | 2.96 s | **25x** |

"Warmed up" is the median of the last 5 of 30 runs inside one JVM. Command-line users never get this; a
long-lived process can approach it.

**Binary size:** ktrs's `ktfmt` is 1.6 MB and its `ktlint` 4.3 MB, against 56.5 MB for ktfmt's native image and
71-75 MB plus a JRE for the jars.

Every scenario, memory use, Spotless numbers, the method and how to reproduce it all:
**[docs/performance.md](docs/performance.md)**.

## How we test

Parity with the original tools is the spec: ktrs runs next to the real jars, and a difference fails the gate unless
it is on a reviewed list in [`tools/parity/known-diffs/`](tools/parity/known-diffs/). A release can't be tagged
without a passing parity run on its commit.

| What | Compared with | On | When |
|---|---|---|---|
| Unit and ported upstream tests (ktfmt's suite, ktlint's rule tests) | Upstream's expected results | Linux, macOS, Windows | Every push and PR |
| Parser | Kotlin compiler's PSI tree (`DebugUtil.psiToString`) | Compiler's fixtures, every corpus file | Fixtures every push, corpus nightly |
| Formatter | ktfmt jar, byte for byte | Corpus in meta, google and kotlinlang styles | Nightly |
| Linter | ktlint jar: violations and `--format` output | Corpus in `ktlint_official`, `intellij_idea`, `android_studio`, with and without experimental rules | Nightly |
| ktlint 1.8 mode, compose-rules | Their jars | Corpus | Nightly |
| CLIs | Jars: stdout, stderr, exit code, written files | Scenario suite, including editor invocations | Nightly |
| Gradle and Maven drop-ins | The original plugins | Fixture builds | Nightly |
| Held-out corpus | Same as the formatter, linter and CLIs | 15,287 files from 20 other projects, which never drove a fix | On demand |
| Fuzzing | Jars, plus crash and hang checks | Mutated real-world files | On demand |

The **corpus** is ~6,000 files from 7 projects, pinned in [`tools/corpus/REVISIONS`](tools/corpus/REVISIONS). The
[nightly parity run](https://github.com/Hexay/ktrs/actions/workflows/parity.yml) is public, and a weekly workflow opens
an issue when ktfmt, ktlint, compose-rules or Kotlin publishes a newer release. On 2026-10-30, `cargo test --workspace`
on Linux gave 922 passed, 0 failed, 3 ignored; that counts ktrs's test functions, not upstream's tests one for one.

- **Held-out corpus.** It checks that corpus work didn't overfit. In its first run, all 2.2M lint violations and
  every ktfmt output matched in all three styles, and `--format` differed on 3 files from one rule, since fixed
  ([research/21](research/21-holdout.md); `tools/holdout/run.sh`).
- **Fuzzing.** The first runs found 4 bugs, now fixed, including exponential parser memory on deeply nested
  generic-looking input ([research/24](research/24-fuzzing.md); `fuzz/`, `tools/fuzz/diff.sh`).

Run them yourself: `cargo test`, then `cargo corpus-diff`, `cargo fmt-diff` and `cargo lint-diff`. The full list of
gates is in [`CLAUDE.md`](CLAUDE.md).

## Why Rust, and when not to use it

- **Why not just count warm-up out?** CLIs, hooks and CI start a new process each time, so that cost is real, and ktrs
  needs no daemon to avoid it. It also isn't the whole gap. Warming up closes most of ktfmt's (24x to 4x on okhttp) but
  little of ktlint's (37x to 25x).
- **Why not a GraalVM native image?** It removes startup for far less work, and for single files the published ktfmt
  image is close enough that you won't notice the difference. See [ktfmt#584](https://github.com/Kotlin/ktfmt/pull/584)
  and [KT-82373](https://youtrack.jetbrains.com/issue/KT-82373/Meta-Distribute-a-GraalVM-compiled-Native-Image-of-kotlinc-or-the-Kotlin-daemon).
  ktrs stays 10-16x ahead on whole projects, in a much smaller binary. We haven't measured PGO builds, which will narrow
  that.
- **Why not Kotlin/Native?** There is no port to measure, so we have no numbers either way.
- **What does it cost?** A second codebase to maintain. ktrs has about 103,000 lines of Rust including tests, against
  about 12,000 in ktfmt's core and 33,000 in ktlint, excluding their tests. That isn't like for like: those tools reuse
  the Kotlin compiler's parser, and ktrs reimplements it. About 20 lines use `unsafe`, in FFI, WASM and the tree builder;
  the parser, formatter and lint crates have none.

**Stay on the originals** if a PGO native image or a warm daemon is fast enough for you, if you rely on rule sets other
than compose-rules (they run on the JVM anyway), or if you need new upstream releases the day they ship.

## Integrations

### Migrating

`ktrs migrate` switches a build's ktfmt-gradle, ktlint-gradle, kotlinter, ktlint-maven-plugin and
Spotless setup to the ktrs drop-ins, editing only ids, coordinates and versions in place. Setups it can't rewrite, such
as a task that runs ktlint from its jar, get a `note:` saying what to change by hand.

```sh
ktrs migrate            # print the edits as a diff; exit 1 if there are any
ktrs migrate --write    # apply them
```

### GitHub Actions

Check a pull request's Kotlin files, with each finding shown as an annotation on the diff:

```yaml
- uses: actions/checkout@v4
  with: { fetch-depth: 0 }         # changed-only needs the history back to the base commit
- uses: Hexay/ktrs@v0.5.3          # Linux, macOS and Windows
  with:
    check: fmt lint                # ktrs fmt --check and ktrs lint (or just one of them)
    changed-only: true             # only the files the pull request changes
    fmt-args: --style kotlinlang   # lint-args likewise
```

SARIF upload, `changed-only` rules and running the binaries yourself:
[docs/ci-integrations.md](docs/ci-integrations.md#github-actions).

### pre-commit

No Rust needed: on first run, the hook downloads the release binaries for its `rev`.

```yaml
- repo: https://github.com/Hexay/ktrs
  rev: v0.5.3
  hooks:
    - id: ktrs-fmt          # also: ktrs-fmt-check, ktfmt (with ktfmt's flags in `args`)
      args: [--style, kotlinlang]
    - id: ktrs-lint         # also: ktrs-lint-format, ktlint (with ktlint's flags in `args`)
```

### Everything else

| Integration | Guide |
|---|---|
| ktfmt-gradle, ktlint-gradle, kotlinter (plugin drop-ins), Spotless, Maven, JVM API | [docs/build-tools.md](docs/build-tools.md) |
| VS Code, IntelliJ, Android Studio, Neovim, Helix, Zed, Emacs | [docs/editors.md](docs/editors.md) |
| Bazel, reviewdog, Danger | [docs/ci-integrations.md](docs/ci-integrations.md) |

## Use the parser as a library

The parser is available on its own as the Rust crate [`kt-syntax`](crates/kt-syntax): a parser for
Kotlin that builds the compiler's PSI tree (same kinds, same nesting, same error elements) with no JVM.
It gives you navigation, byte ranges and line/column positions, syntax errors as nodes, comments and
parsed KDoc, and text edits for codemods. `kt-syntax` is the stable API; the `ktrs-*` crates are internals. See its
[README](crates/kt-syntax/README.md) for examples.

## Maintenance

ktrs is maintained by [@Hexay](https://github.com/Hexay). It tracks ktfmt 0.65, ktlint
2.0.0-ALPHA-4 (plus 1.8.0 in compatibility mode), compose-rules 0.6.8 and the Kotlin 2.4.21 parser. New upstream
releases are ported and re-checked against the parity gates before a ktrs release. If ktrs output ever differs from
ktfmt or ktlint on your code, that's a bug: please [open an issue](https://github.com/Hexay/ktrs/issues) with the
file, or a snippet that reproduces it, and the command line you used.

## Contributing

```sh
tools/sync-kotlin.sh                  # pinned upstream sources + vendored test fixtures
tools/psi-dump/psi-dump.sh one X.kt   # reference PSI tree from the real compiler (needs a JDK)
cargo xtask codegen                   # regenerate SyntaxKind from crates/ktrs-syntax/kinds.tsv
cargo test
```

[`CLAUDE.md`](CLAUDE.md) lists the crate layout and every parity gate. Design notes are in
[`research/`](research/).

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option. ktrs
contains code and test data ported from the Kotlin compiler, the IntelliJ Platform, ktfmt,
google-java-format, ec4j (Apache-2.0), ktlint and ktfmt-gradle (MIT). See [NOTICE](NOTICE).
