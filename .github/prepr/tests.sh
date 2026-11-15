#!/bin/bash
# Pre-PR check: run, unmodified, every tests/*.sh that compiles a changed
# source file, on the branch (./b) and on its base (./a), and report only the
# differences. A test that fails the same way on both is the environment or
# an old failure, not this branch.
#   bash tests.sh        (after trees.sh; run from the directory holding a/ b/)
set -uo pipefail
RAIZ=$PWD
OUT=$RAIZ/out-tests; mkdir -p "$OUT"
JOBS=${PREPR_JOBS:-4}
TMO=${PREPR_TEST_TIMEOUT:-240}

# 1. Changed code files (not headers: a test "compiles a changed file" when
#    its script, or a tests/ file the script builds, names it).
grep -E '^(src|rust|tools/tpk/libass-nv|android/app/src)/' changed.txt \
  | grep -E '\.(c|inc|rs|kt|cs|py|sh)$' | sed 's#.*/##' | sort -u > "$OUT/nomes.txt"
re=$(sed 's/[.[\*^$()+?{|]/\\&/g' "$OUT/nomes.txt" | paste -sd'|')
ER="(^|[^A-Za-z0-9_])($re)([^A-Za-z0-9_]|\$)"
cd "$RAIZ/b"
# tests/ files (not scripts) that name a changed file, or changed themselves
{ grep -lE "$ER" tests/*.c tests/*.h tests/*.py tests/*.inc 2>/dev/null
  grep -E '^tests/' "$RAIZ/changed.txt" | grep -vE '\.sh$'; } | sed 's#.*/##' | sort -u > "$OUT/aux.txt"
re2=$(cat "$OUT/nomes.txt" "$OUT/aux.txt" | sort -u | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd'|')
ER2="(^|[^A-Za-z0-9_])($re2)([^A-Za-z0-9_]|\$)"
{ grep -lE "$ER2" tests/*.sh
  grep -E '^tests/.*\.sh$' "$RAIZ/changed.txt"
  for g in i18n mkvcore_paridade cache_contrato tpk40_tls; do echo "tests/$g.sh"; done
} | sort -u | while read -r f; do [ -f "$f" ] && echo "$f"; done \
  | grep -vE '(_shot|cinematic|director|webp-tizen|webp-vidaa-st|tizen-clock|salvospainel_perf|fluidez_perf_player|fluidez_perf_guia)\.sh$' \
  > "$OUT/lista.txt"
echo "tests picked: $(wc -l < "$OUT/lista.txt") of $(ls tests/*.sh | wc -l)"

um() { # um <side> <script> -> "<script> <rc>"
  local lado=$1 f=$2 n; n=$(basename "$f" .sh)
  if [ ! -f "$RAIZ/$lado/$f" ]; then echo "$f absent"; return; fi
  ( cd "$RAIZ/$lado" && timeout -k 5 "$TMO" bash "$f" > "$OUT/$lado.$n.log" 2>&1 ); echo "$f $?"
}
export -f um; export RAIZ OUT TMO
rodar() { # rodar <side> <list> <jobs>
  xargs -a "$2" -P "$3" -I{} bash -c 'um "$0" "$1"' "$1" {} | sort > "$OUT/$1.res"
}
assin() { # normalized first error line of a failed log
  grep -m1 -iE 'error|undefined reference|FALH|FAIL|assert|No such file|not found|Abort|Segmentation|timed out' "$1" 2>/dev/null \
    | sed -E 's#/tmp/[A-Za-z0-9._/-]+#TMP#g; s#[0-9]+#N#g' | cut -c1-160
}
rodar a "$OUT/lista.txt" "$JOBS"
rodar b "$OUT/lista.txt" "$JOBS"

classificar() {
  : > "$OUT/dif.txt"
  join "$OUT/a.res" "$OUT/b.res" | while read -r f ra rb; do
    n=$(basename "$f" .sh)
    if [ "$ra" = "$rb" ] && [ "$ra" = 0 ]; then echo "PASS_BOTH $f"
    elif [ "$ra" = absent ] && [ "$rb" = 0 ]; then echo "NEW_PASS $f"
    elif [ "$ra" = absent ]; then echo "NEW_FAIL $f rc=$rb | $(assin "$OUT/b.$n.log")"
    elif [ "$ra" = 0 ]; then echo "REGRESSION $f rc=$rb | $(assin "$OUT/b.$n.log")"
    elif [ "$rb" = 0 ]; then echo "FIXED $f (base rc=$ra)"
    else
      sa=$(assin "$OUT/a.$n.log"); sb=$(assin "$OUT/b.$n.log")
      if [ "$sa" = "$sb" ]; then echo "FAIL_BOTH_SAME $f | $sb"; else echo "FAIL_BOTH_DIFF $f | base: $sa | branch: $sb"; fi
    fi
  done > "$OUT/classes.txt"
}
classificar
# 2. Anything that looks like a difference is run again, one at a time, on
#    both sides: parallel runs can collide on ports and temp names.
grep -E '^(REGRESSION|NEW_FAIL|FAIL_BOTH_DIFF|FIXED)' "$OUT/classes.txt" | awk '{print $2}' > "$OUT/de-novo.txt"
if [ -s "$OUT/de-novo.txt" ]; then
  echo "running again one at a time: $(wc -l < "$OUT/de-novo.txt")"
  cp "$OUT/a.res" "$OUT/a.res1"; cp "$OUT/b.res" "$OUT/b.res1"
  for lado in a b; do
    xargs -a "$OUT/de-novo.txt" -P 1 -I{} bash -c 'um "$0" "$1"' "$lado" {} | sort > "$OUT/$lado.res2"
    { grep -vFf <(awk '{print $1" "}' "$OUT/$lado.res2") "$OUT/$lado.res1"; cat "$OUT/$lado.res2"; } | sort > "$OUT/$lado.res"
  done
  classificar
fi

# 3. New tests that know SANITIZE=1 also run under ASan/UBSan.
: > "$OUT/san.txt"
grep -E '^(NEW_PASS|NEW_FAIL)' "$OUT/classes.txt" | awk '{print $2}' | while read -r f; do
  grep -q SANITIZE "$RAIZ/b/$f" || continue
  n=$(basename "$f" .sh)
  ( cd "$RAIZ/b" && SANITIZE=1 timeout -k 5 "$TMO" bash "$f" > "$OUT/b.$n.san.log" 2>&1 ); echo "SANITIZE=1 $f rc=$?" >> "$OUT/san.txt"
done

{
  echo "### Tests that compile a changed file: branch vs base"
  echo '```'
  awk '{print $1}' "$OUT/classes.txt" | sort | uniq -c
  echo '```'
  for c in REGRESSION NEW_FAIL FAIL_BOTH_DIFF FIXED NEW_PASS; do
    if grep -q "^$c " "$OUT/classes.txt"; then echo "**$c**"; echo '```'; grep "^$c " "$OUT/classes.txt" | cut -c1-400; echo '```'; fi
  done
  if [ -s "$OUT/san.txt" ]; then echo "**New tests under ASan/UBSan**"; echo '```'; cat "$OUT/san.txt"; echo '```'; fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
for f in $(grep -E '^(REGRESSION|NEW_FAIL)' "$OUT/classes.txt" | awk '{print $2}'); do
  n=$(basename "$f" .sh); echo "::group::branch log: $f"; tail -n 40 "$OUT/b.$n.log"; echo "::endgroup::"
done
grep -l 'rc=[1-9]' "$OUT/san.txt" >/dev/null 2>&1 && for l in "$OUT"/b.*.san.log; do echo "::group::$l"; tail -n 40 "$l"; echo "::endgroup::"; done
if grep -qE '^(REGRESSION|NEW_FAIL)' "$OUT/classes.txt" || grep -q 'rc=[1-9]' "$OUT/san.txt"; then exit 1; fi
