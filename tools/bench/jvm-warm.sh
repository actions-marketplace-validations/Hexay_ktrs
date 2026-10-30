#!/usr/bin/env bash
# Warm-JVM baseline for the jars public.sh downloads: okhttp repeatedly in one JVM (JvmWarm.java). Run public.sh first.
#   tools/bench/jvm-warm.sh [ITERATIONS] [TAIL]    (default 30, 5). Env: CACHE as in public.sh. Prints every iteration and a summary per tool.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ITERATIONS=${1:-30} TAIL=${2:-5}
CACHE=${CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ktrs-bench}
okhttp=$CACHE/corpus/tree/okhttp
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp -R "$okhttp" "$W/tree"; cp "$CACHE/corpus/tree/.editorconfig" "$W/tree/"

warm() { # label cwd jar main args...
  local label=$1 cwd=$2 jar=$3 main=$4; shift 4
  echo "== $label"
  (cd "$cwd" && java -Djava.security.manager=allow -cp "$jar" "$here/JvmWarm.java" "$ITERATIONS" "$TAIL" "$main" "$@" 2> /dev/null)
}
warm "ktfmt format okhttp" "$W" "$CACHE/jars/ktfmt-0.65-with-dependencies.jar" org.jetbrains.kotlinx.ktfmt.cli.Main --quiet "$W/tree"
warm "ktlint lint okhttp" "$okhttp" "$CACHE/jars/ktlint-2.0.0-ALPHA-4" io.github.ktlint.core.Main --relative
