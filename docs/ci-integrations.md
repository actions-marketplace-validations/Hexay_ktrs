# CI integrations

## GitHub Actions

The basic setup is in the [README](../README.md#github-actions).

`sarif: true` also uploads the lint findings to GitHub code scanning, so they show up in the Security tab and
stay tracked across commits, without the annotation limit. The job needs `permissions: { contents: read,
security-events: write }`, and private repositories need GitHub Code Security:

```yaml
- uses: Hexay/ktrs@v0.5.3
  with:
    check: lint
    sarif: true                    # sarif-category: <name> keeps several uploads apart
```

`changed-only` compares with the pull request's base commit. On a push it compares with the commit
before the push, or with the default branch for a new branch or a force push; `base: <ref>` overrides
this. Without `check`, the action only installs the binaries, and you run them yourself:

```yaml
- uses: Hexay/ktrs@v0.5.3
- run: ktrs fmt --check --style kotlinlang
- run: ktrs lint --reporter github --changed-since origin/main
```

`--changed-since <ref>` (`ktrs fmt` and `ktrs lint`) keeps the files that differ from the merge base
of `<ref>` and `HEAD`, including uncommitted and untracked ones. `--reporter github` (`ktrs lint` and
`ktrs fmt --check`) prints the findings as annotations. GitHub shows at most 10 annotations per step;
the job log has all of them.

## Bazel

[rules_lint](https://github.com/aspect-build/rules_lint) 2.9.1 takes the binaries where it takes the
jars (checked on Bazel 8). Each release has a [rules_multitool](https://github.com/bazel-contrib/rules_multitool) lockfile
for `ktrs`, `ktfmt` and `ktlint` on all six platforms, `ktrs-<tag>.multitool.lock.json`; save it as
`ktrs.lock.json` at the workspace root:

```python
# MODULE.bazel
bazel_dep(name = "aspect_rules_lint", version = "2.9.1")
bazel_dep(name = "rules_multitool", version = "1.11.1")

multitool = use_extension("@rules_multitool//multitool:extension.bzl", "multitool")
multitool.hub(lockfile = "//:ktrs.lock.json")
use_repo(multitool, "multitool")
```

```python
# tools/format/BUILD.bazel: `bazel run //tools/format` rewrites, `bazel run //tools/format:format.check` checks
load("@aspect_rules_lint//format:defs.bzl", "format_multirun")

format_multirun(
    name = "format",
    kotlin = "@multitool//tools/ktfmt",
    kotlin_check_args = ["--kotlinlang-style", "--set-exit-if-changed", "--dry-run"],
    kotlin_fix_args = ["--kotlinlang-style"],
)
```

```python
# tools/lint/linters.bzl
load("@aspect_rules_lint//lint:ktlint.bzl", "lint_ktlint_aspect")
load("@aspect_rules_lint//lint:lint_test.bzl", "lint_test")

ktlint = lint_ktlint_aspect(
    binary = Label("@multitool//tools/ktlint"),
    editorconfig = Label("//:.editorconfig"),
    baseline_file = Label("//:ktlint-baseline.xml"),   # required by rules_lint; may hold no entries
    args = ["--log-level=none"],                       # ktlint logs to stdout, which is the report
)

ktlint_test = lint_test(aspect = ktlint)               # ktlint_test(name = ..., srcs = [":lib"]) for `bazel test`
```

```sh
bazel build //... --aspects=//tools/lint:linters.bzl%ktlint --output_groups=rules_lint_human
```

- The lint action sees only what Bazel declares: the target's sources and the one `editorconfig`
  file. Nested `.editorconfig` files are not applied. Give the root one `root = true`, or ktlint
  keeps looking above Bazel's output directory and can pick up a stray file there.
- It needs Bazel's sandbox. With `--spawn_strategy=local` ktlint finds no files and the target passes.
- rules_lint's aspect still asks for a JDK, which the binary never starts. A machine without Java needs
  `--java_runtime_version=remotejdk_21`.
- rules_kotlin's own `ktlint_test` and `ktlint_fix` take no binary, so they still run the jar.

A complete workspace, run in CI: [bazel/e2e/rules_lint](../bazel/e2e/rules_lint).

## reviewdog

[reviewdog](https://github.com/reviewdog/reviewdog) posts violations as review comments on the
changed lines, and fixes as suggested changes. It reads the `ktlint` binary's checkstyle report, or
a diff:

```yaml
- uses: reviewdog/action-setup@v1
- name: Violations as review comments
  env:
    REVIEWDOG_GITHUB_API_TOKEN: ${{ github.token }}
  run: |
    ktlint --relative --reporter=checkstyle,output=ktlint.xml || true
    reviewdog -f=checkstyle -name=ktlint -reporter=github-pr-review -filter-mode=added < ktlint.xml
```

```yaml
- run: ktlint -F || true          # or: ktfmt --kotlinlang-style src/
- uses: reviewdog/action-suggester@v1   # turns the working tree's diff into suggested changes
  with:
    tool_name: ktlint
```

`ktrs lint --reporter checkstyle` gives the same report. For `-f=sarif`, leave out `--relative`:
ktlint's SARIF report declares its paths as relative to the home directory, so with `--relative`
reviewdog matches none of them.

## Danger

[Danger](https://danger.systems) plugins work unchanged:

- [danger-ktlint](https://github.com/mataku/danger-ktlint) (Ruby) runs `ktlint <changed files>
  --reporter=json --relative --log-level=none` from `PATH`, so the binary only has to be there. With
  `ktlint.skip_lint = true` it reads `ktlint.report_file`, written by
  `ktlint --relative --reporter=json,output=ktlint.json`.
- [ktlint-danger-kotlin](https://github.com/Bastosss77/ktlint-danger-kotlin) parses a report file and
  picks the parser by extension: `--reporter=json,output=ktlint.json`,
  `--reporter=checkstyle,output=ktlint.xml` or `--reporter=sarif,output=ktlint.sarif`.
- Checkstyle plugins (danger-checkstyle_format, danger-plugin-lint-report) read the `ktlint.xml` above.
