#!/usr/bin/env bash
# Reproducible benchmark: ktrs's `ktfmt`/`ktlint` binaries vs the pinned upstream jars and native images, timed by hyperfine on the
# public corpus pinned in tools/bench/REVISIONS. Linux and macOS (bash 3.2+). What it measures and how the numbers
# relate to the README: research/23-public-bench.md.
#
#   tools/bench/public.sh [--only LIST] [--ktlint "VERSION..."] [--runs N] [--warmup N] [--out DIR] [--list]
#
# LIST: scenario ids and/or groups (all, quick, fmt, lint), comma or space separated; default all. --ktlint: the
# ktlint jars to compare (default "2.0.0-ALPHA-4 1.8.0"). Env: KTRS_BIN = dir with the ktfmt/ktlint/ktrs binaries
# (default target/dist: `cargo build --profile dist --bins`); CACHE = jars + corpus (default ~/.cache/ktrs-bench);
# CORPUS = a ready .kt/.kts tree with one root .editorconfig (default: fetched into CACHE); HYPERFINE; ONE_CPU = the
# CPU for the 1-core scenarios (Linux only, default 0). Results: OUT/<id>.{json,md} and OUT/summary.md.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

KTFMT_VERSION=0.65
KTFMT_SHA256=aba9753b6ab387926179ab7318ba8e0c33dad483ebc72f633e79522265b15214
ktlint_sha256() {
  case $1 in
    2.0.0-ALPHA-4) echo fb28b3cd57116d1de78867ebd8ce398ede91e91b280b33dc367e0108336b79f1 ;;
    1.8.0) echo a3fd620207d5c40da6ca789b95e7f823c54e854b7fade7f613e91096a3706d75 ;;
    *) die "no pinned sha256 for ktlint $1 (add it to ktlint_sha256)" ;;
  esac
}
# GraalVM native images published upstream; empty on platforms with no pin (then only the jars run).
KTLINT_NATIVE_VERSION=2.0.0-ALPHA-4
case "$(uname -sm)" in
  "Linux x86_64")
    KTFMT_NATIVE_ASSET=ktfmt-linux-x86_64-$KTFMT_VERSION
    KTFMT_NATIVE_SHA256=3684327b092db9b76fffcb9525decf73f8331ed17e00ce3232769c11cd36d352
    KTLINT_NATIVE_ASSET=ktlint_linux-x86-64
    KTLINT_NATIVE_SHA256=5775542be982b9c795750c7809ab7c291e3d946eab5214bd3c475bf497fe0073 ;;
  "Darwin arm64")
    KTFMT_NATIVE_ASSET=ktfmt-macos-aarch64-$KTFMT_VERSION
    KTFMT_NATIVE_SHA256=d10ec46dadc4ae19e5b8ddc72d10ce45e5be35d632ce9e73c9b8a59d2147fb85
    KTLINT_NATIVE_ASSET=ktlint_darwin-arm64
    KTLINT_NATIVE_SHA256=c749d8d6b081288c68b0e8427c6f977a4fd06bf45d1cc68d330cc31262a57556 ;;
  *) KTFMT_NATIVE_ASSET= KTLINT_NATIVE_ASSET= ;;
esac

FMT_ALL="fmt-stdin fmt-precommit fmt-check-okhttp fmt-okhttp fmt-okhttp-1core fmt-corpus"
LINT_ALL="lint-stdin lint-file lint-okhttp lint-okhttp-1core lint-corpus format-okhttp format-corpus"
QUICK="fmt-stdin fmt-precommit fmt-check-okhttp fmt-okhttp fmt-corpus lint-stdin lint-file lint-okhttp lint-corpus format-okhttp"

die() { echo "public.sh: $*" >&2; exit 1; }

ONLY=all KTLINTS="2.0.0-ALPHA-4 1.8.0" RUNS=5 WARMUP=1 OUT=$root/target/bench/public
while (($#)); do
  case $1 in
    --only) ONLY=$2; shift 2 ;; --ktlint) KTLINTS=$2; shift 2 ;; --runs) RUNS=$2; shift 2 ;;
    --warmup) WARMUP=$2; shift 2 ;; --out) OUT=$2; shift 2 ;;
    --list) echo "fmt: $FMT_ALL"; echo "lint: $LINT_ALL"; echo "quick: $QUICK"; exit 0 ;;
    *) die "unknown argument $1" ;;
  esac
done

SELECTED=
for s in ${ONLY//,/ }; do
  case $s in
    all) SELECTED+=" $FMT_ALL $LINT_ALL" ;; quick) SELECTED+=" $QUICK" ;;
    fmt) SELECTED+=" $FMT_ALL" ;; lint) SELECTED+=" $LINT_ALL" ;;
    *) [[ " $FMT_ALL $LINT_ALL " == *" $s "* ]] || die "unknown scenario $s (--list)"; SELECTED+=" $s" ;;
  esac
done
want() { [[ " $SELECTED " == *" $1 "* ]]; }
want_any() { local s; for s in $1; do want "$s" && return 0; done; return 1; }
if [[ $(uname -s) != Linux ]] || ! command -v taskset > /dev/null; then
  want_any "fmt-okhttp-1core lint-okhttp-1core" && echo "1-core scenarios skipped: no taskset on this OS" >&2
  SELECTED=$(echo "$SELECTED" | tr ' ' '\n' | { grep -v -- '-1core$' || true; } | tr '\n' ' ')
fi

q() { printf '%q' "$1"; }
sha256() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
fetch_pinned() { # file url sha256
  [[ -f $1 && $(sha256 "$1") == "$3" ]] && return 0
  echo "downloading $2" >&2
  curl -fsSL --retry 3 -o "$1.part" "$2"
  [[ $(sha256 "$1.part") == "$3" ]] || die "sha256 mismatch for $2 (got $(sha256 "$1.part"))"
  mv "$1.part" "$1"; chmod +x "$1"
}

HYPERFINE=${HYPERFINE:-$(command -v hyperfine || echo "$HOME/.cargo/bin/hyperfine")}
[[ -x $HYPERFINE ]] || die "hyperfine not found (cargo install hyperfine, or set HYPERFINE)"
command -v java > /dev/null || die "java not on PATH"
KTRS_BIN=$(cd "${KTRS_BIN:-$root/target/dist}" && pwd) || die "KTRS_BIN missing (cargo build --profile dist --bins)"
CACHE=${CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ktrs-bench}
ONE_CPU=${ONE_CPU:-0}
mkdir -p "$CACHE/jars" "$OUT"
rm -f "$OUT"/*.json "$OUT"/*.md "$OUT/scenarios.tsv"

KTFMT_JAR=$CACHE/jars/ktfmt-$KTFMT_VERSION-with-dependencies.jar
want_any "$FMT_ALL" && fetch_pinned "$KTFMT_JAR" \
  "https://repo1.maven.org/maven2/org/jetbrains/kotlinx/ktfmt/$KTFMT_VERSION/ktfmt-$KTFMT_VERSION-with-dependencies.jar" "$KTFMT_SHA256"
if want_any "$LINT_ALL"; then
  for v in $KTLINTS; do
    sha=$(ktlint_sha256 "$v")
    fetch_pinned "$CACHE/jars/ktlint-$v" "https://github.com/pinterest/ktlint/releases/download/$v/ktlint" "$sha"
  done
fi
KTFMT_NATIVE= KTLINT_NATIVE=
if [[ -n $KTFMT_NATIVE_ASSET ]]; then
  if want_any "$FMT_ALL"; then
    fetch_pinned "$CACHE/jars/$KTFMT_NATIVE_ASSET.tar.gz" \
      "https://github.com/Kotlin/ktfmt/releases/download/v$KTFMT_VERSION/$KTFMT_NATIVE_ASSET.tar.gz" "$KTFMT_NATIVE_SHA256"
    tar -xzf "$CACHE/jars/$KTFMT_NATIVE_ASSET.tar.gz" -C "$CACHE/jars"
    KTFMT_NATIVE=$CACHE/jars/$KTFMT_NATIVE_ASSET/ktfmt
  fi
  if want_any "$LINT_ALL"; then
    KTLINT_NATIVE=$CACHE/jars/$KTLINT_NATIVE_ASSET-$KTLINT_NATIVE_VERSION
    fetch_pinned "$KTLINT_NATIVE" \
      "https://github.com/pinterest/ktlint/releases/download/$KTLINT_NATIVE_VERSION/$KTLINT_NATIVE_ASSET" "$KTLINT_NATIVE_SHA256"
  fi
fi

if [[ -z ${CORPUS:-} ]]; then
  "$root/tools/holdout/fetch.sh" "$CACHE/corpus" "$here/REVISIONS" >&2
  CORPUS=$CACHE/corpus/tree
  printf 'root = true\n\n[*.{kt,kts}]\nktlint_code_style = ktlint_official\n' > "$CORPUS/.editorconfig"
fi
[[ -f $CORPUS/.editorconfig ]] || die "$CORPUS has no root .editorconfig"
okhttp=$CORPUS/okhttp
kotlin_files() { find "$1" -type f \( -name '*.kt' -o -name '*.kts' \) | LC_ALL=C sort; }
editor_file=$(find "$okhttp" -name '*.kt' -size +8k -size -16k | LC_ALL=C sort | awk 'NR == 1')
one_dir=$okhttp/okhttp/src/commonJvmAndroid/kotlin/okhttp3
[[ -f $editor_file && -f $one_dir/Credentials.kt ]] || die "$okhttp is not the pinned okhttp"

# Gotcha: a crash exits 1 like "lint errors found", and --ignore-failure would then time the crash as a fast run.
if [[ -n $KTLINT_NATIVE ]]; then
  probe=$(cd "$one_dir" && "$KTLINT_NATIVE" --relative Credentials.kt 2>&1 || true)
  if [[ $probe == *"Exception in thread"* ]]; then
    echo "ktlint native image crashes on this platform: not benchmarked (research/37)" >&2
    KTLINT_NATIVE= KTLINT_NATIVE_ASSET=
  fi
fi

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T=$W/tree

{
  echo "- $(uname -sm), $(getconf _NPROCESSORS_ONLN) CPUs; $(java -version 2>&1 | head -1); $("$HYPERFINE" --version)"
  echo "- $("$KTRS_BIN/ktrs" --version 2>&1 | head -1) ($KTRS_BIN); ktfmt $KTFMT_VERSION jar; ktlint jars: $KTLINTS;" \
    "native images: ${KTFMT_NATIVE_ASSET:-none} ${KTLINT_NATIVE_ASSET:+$KTLINT_NATIVE_ASSET $KTLINT_NATIVE_VERSION}"
  echo "- corpus $(kotlin_files "$CORPUS" | wc -l | tr -d ' ') files, okhttp $(kotlin_files "$okhttp" | wc -l | tr -d ' ');" \
    "editor file ${editor_file#"$CORPUS"/} ($(wc -c < "$editor_file" | tr -d ' ') bytes)"
  echo "- hyperfine: $WARMUP warm-up, $RUNS runs per command; commands run one after another, not interleaved"
} > "$OUT/env.md"
cat "$OUT/env.md"

HOPTS=()
# bench id label ktrs-cmd "name=cmd"... ; HOPTS holds extra hyperfine options (--setup/--prepare) for this call only.
bench() {
  local id=$1 label=$2 ours=$3 pair; shift 3
  if ! want "$id"; then HOPTS=(); return 0; fi
  local cmds=(-n ktrs "$ours")
  for pair in "$@"; do cmds+=(-n "${pair%%=*}" "${pair#*=}"); done
  echo; echo "== $id: $label"
  local start=$SECONDS
  "$HYPERFINE" --warmup "$WARMUP" --runs "$RUNS" --ignore-failure --style basic \
    --export-json "$OUT/$id.json" --export-markdown "$OUT/$id.md" ${HOPTS[@]+"${HOPTS[@]}"} "${cmds[@]}"
  printf '%s\t%s\n' "$id" "$label" >> "$OUT/scenarios.tsv"
  echo "== $id took $((SECONDS - start)) s"
  HOPTS=()
}
copy_to_tree() { echo "rm -rf $(q "$T") && cp -R $(q "$1") $(q "$T") && cp $(q "$CORPUS/.editorconfig") $(q "$T/")"; }
pin1() { echo "taskset -c $ONE_CPU"; }

KTFMT=$(q "$KTRS_BIN/ktfmt") JAR="java -jar $(q "$KTFMT_JAR")" JN="ktfmt $KTFMT_VERSION"
# fmt_bench id label args [pin]: ktrs, then the jar, then the native image if there is one for this platform.
fmt_bench() {
  local id=$1 label=$2 args=$3 pre=${4:+$4 }
  local cmds=("$pre$KTFMT $args" "$JN=$pre$JAR $args")
  [[ -n $KTFMT_NATIVE ]] && cmds+=("$JN native=$pre$(q "$KTFMT_NATIVE") $args")
  bench "$id" "$label" "${cmds[@]}"
}
precommit=""
for f in $(kotlin_files "$okhttp" | awk 'NR <= 10'); do precommit+=" $(q "$T/${f#"$okhttp"/}")"; done
okhttp_n=$(kotlin_files "$okhttp" | wc -l | tr -d ' ') corpus_n=$(kotlin_files "$CORPUS" | wc -l | tr -d ' ')

fmt_bench fmt-stdin "ktfmt: editor, one $(($(wc -c < "$editor_file") / 1000)) KB file on stdin" "- < $(q "$editor_file")"
HOPTS=(--setup "$(copy_to_tree "$okhttp")")
fmt_bench fmt-precommit "ktfmt: pre-commit, 10 files" "--quiet$precommit"
HOPTS=(--setup "$(copy_to_tree "$okhttp")")
fmt_bench fmt-check-okhttp "ktfmt: CI check on okhttp ($okhttp_n files, -n --set-exit-if-changed)" "-n --set-exit-if-changed $(q "$T")"
HOPTS=(--setup "$(copy_to_tree "$okhttp")")
fmt_bench fmt-okhttp "ktfmt: format okhttp in place" "--quiet $(q "$T")"
HOPTS=(--setup "$(copy_to_tree "$okhttp")")
fmt_bench fmt-okhttp-1core "ktfmt: format okhttp in place, 1 core" "--quiet $(q "$T")" "$(pin1)"
HOPTS=(--setup "$(copy_to_tree "$CORPUS")")
fmt_bench fmt-corpus "ktfmt: format the corpus in place ($corpus_n files)" "--quiet $(q "$T")"

# ktlint: cwd = the project and --relative, as in tools/bench/lint-e2e.sh. $1 = what follows `cd DIR &&`.
ktlint_cmds() { # dir args [pin]
  local v pre="cd $(q "$1") && ${3:+$3 }"
  echo "$pre$(q "$KTRS_BIN/ktlint") $2"
  for v in $KTLINTS; do echo "ktlint $v=$pre$(q "$CACHE/jars/ktlint-$v") $2"; done
  [[ -z $KTLINT_NATIVE ]] || echo "ktlint $KTLINT_NATIVE_VERSION native=$pre$(q "$KTLINT_NATIVE") $2"
}
lint_bench() { # id label dir args [pin]
  local id=$1 label=$2 lines=() line
  while IFS= read -r line; do lines+=("$line"); done < <(ktlint_cmds "$3" "$4" "${5:-}")
  bench "$id" "$label" "${lines[@]}"
}
lint_bench lint-stdin "ktlint: editor, one $(($(wc -c < "$editor_file") / 1000)) KB file on stdin" \
  "$(dirname "$editor_file")" "--stdin < $(q "$editor_file")"
lint_bench lint-file "ktlint: lint one file (Credentials.kt)" "$one_dir" "--relative Credentials.kt"
lint_bench lint-okhttp "ktlint: lint okhttp ($okhttp_n files)" "$okhttp" --relative
lint_bench lint-okhttp-1core "ktlint: lint okhttp, 1 core" "$okhttp" --relative "$(pin1)"
lint_bench lint-corpus "ktlint: lint the corpus ($corpus_n files)" "$CORPUS" --relative
HOPTS=(--prepare "$(copy_to_tree "$okhttp")")
lint_bench format-okhttp "ktlint: autocorrect okhttp (-F, fresh copy)" "$T" "--relative -F"
HOPTS=(--prepare "$(copy_to_tree "$CORPUS")")
lint_bench format-corpus "ktlint: autocorrect the corpus (-F, fresh copy)" "$T" "--relative -F"

echo
python3 "$here/public_summary.py" "$OUT" | tee "$OUT/summary.md"
