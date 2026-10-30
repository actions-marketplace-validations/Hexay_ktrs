#!/usr/bin/env python3
"""spotlessApply on okhttp with ktrs vs ktfmt, in a fresh and a warm Gradle daemon. See docs/performance.md.

    tools/bench/spotless.py [--runs N] [--warm-up N]

Needs public.sh's corpus in CACHE (default ~/.cache/ktrs-bench) and the Gradle wrapper in java/. Each step is timed
against a baseline that only trims whitespace; the formatter's share is the difference. Exits 1 if the trees differ.
"""

import argparse
import filecmp
import os
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GRADLEW = ROOT / "java" / "gradlew"
SPOTLESS_VERSION = "8.10.4"
KTFMT_VERSION = "0.65"
KTRS_VERSION = "0.5.3"

STEPS = {
    "baseline": ("", "trimTrailingWhitespace()"),
    "ktrs": (
        f'buildscript {{ repositories {{ mavenCentral() }}; dependencies {{ classpath("io.github.hexay:ktrs:{KTRS_VERSION}") }} }}\n',
        "addStep(io.github.hexay.ktrs.spotless.KtrsStep.create(io.github.hexay.ktrs.KtrsOptions.kotlinlang()))",
    ),
    "ktfmt": ("", f'ktfmt("{KTFMT_VERSION}").kotlinlangStyle()'),
}


def write_project(project, name, okhttp):
    prelude, step = STEPS[name]
    shutil.copytree(okhttp, project / "src")
    (project / "settings.gradle.kts").write_text(f'rootProject.name = "bench-{name}"\n')
    (project / "gradle.properties").write_text("org.gradle.jvmargs=-Xmx2g\n")
    (project / "build.gradle.kts").write_text(
        f'{prelude}plugins {{ id("com.diffplug.spotless") version "{SPOTLESS_VERSION}" }}\n'
        "repositories { mavenCentral() }\n"
        f'spotless {{ kotlin {{ target("src/**/*.kt"); {step} }} }}\n'
    )


def gradle(project, *args):
    subprocess.run([GRADLEW, "-p", project, "--console=plain", "-q", *args], check=True, stdout=subprocess.DEVNULL)


def apply_seconds(project):
    # --rerun-tasks: Spotless is up to date otherwise, and would time nothing.
    start = time.monotonic()
    gradle(project, "spotlessApply", "--rerun-tasks")
    return time.monotonic() - start


def measure(project, runs, warm_up):
    gradle(project, "--stop")
    apply_seconds(project)  # downloads, and leaves the tree formatted
    fresh = []
    for _ in range(runs):
        gradle(project, "--stop")
        fresh.append(apply_seconds(project))
    for _ in range(warm_up):
        apply_seconds(project)
    warm = [apply_seconds(project) for _ in range(runs)]
    gradle(project, "--stop")
    return statistics.median(fresh), statistics.median(warm)


def trees_differ(a, b):
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or filecmp.cmpfiles(a, b, cmp.common_files, shallow=False)[1]:
        return True
    return any(trees_differ(Path(a) / d, Path(b) / d) for d in cmp.common_dirs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warm-up", type=int, default=5)
    args = parser.parse_args()
    cache = Path(os.environ.get("CACHE", Path.home() / ".cache/ktrs-bench"))
    okhttp = cache / "corpus/tree/okhttp"
    files = sum(1 for _ in okhttp.rglob("*.kt"))

    with tempfile.TemporaryDirectory() as tmp:
        results = {}
        for name in STEPS:
            project = Path(tmp) / name
            project.mkdir()
            write_project(project, name, okhttp)
            results[name] = measure(project, args.runs, args.warm_up)
        differ = trees_differ(Path(tmp) / "ktrs/src", Path(tmp) / "ktfmt/src")

    print(f"Spotless {SPOTLESS_VERSION}, okhttp {files} files, median of {args.runs}")
    print("| | baseline total | ktrs total | ktfmt total | ktrs share | ktfmt share |")
    print("|---|--:|--:|--:|--:|--:|")
    for i, label in enumerate(["fresh daemon", "warm daemon"]):
        base, ktrs, ktfmt = (results[n][i] for n in STEPS)
        print(f"| {label} | {base:.2f} s | {ktrs:.2f} s | {ktfmt:.2f} s | {ktrs - base:.2f} s | {ktfmt - base:.2f} s |")
    print(f"ktrs and ktfmt {KTFMT_VERSION} output: {'DIFFERENT' if differ else 'identical'}")
    raise SystemExit(1 if differ else 0)


if __name__ == "__main__":
    main()
