#!/bin/bash
# Pre-PR check: the Linux desktop build (tools/linux.sh --build), which
# compiles every src/*.c without any TV define, on the base (./a) and on the
# branch (./b), with a compiler that makes implicit declarations, int
# conversions and wrong pointer types fatal.
#   bash linux.sh        (after trees.sh; run from the directory holding a/ b/)
set -uo pipefail
RAIZ=$PWD
OUT=$RAIZ/out-linux; mkdir -p "$OUT"
CCX="${PREPR_CC:-gcc-14} -Werror=implicit-function-declaration -Werror=int-conversion -Werror=incompatible-pointer-types"
for lado in a b; do
  ( cd "$RAIZ/$lado" && CC="$CCX" bash tools/linux.sh --build > "$OUT/$lado.log" 2>&1 ); echo $? > "$OUT/$lado.rc"
  if [ -f "$RAIZ/$lado/build/linux/nuvio-native-legacy" ]; then stat -c %s "$RAIZ/$lado/build/linux/nuvio-native-legacy" > "$OUT/$lado.size"; else echo 0 > "$OUT/$lado.size"; fi
done
ra=$(cat "$OUT/a.rc"); rb=$(cat "$OUT/b.rc")
{
  echo "### Linux desktop build (tools/linux.sh --build)"
  echo "- base: exit $ra, binary $(cat "$OUT/a.size") bytes"
  echo "- branch: exit $rb, binary $(cat "$OUT/b.size") bytes"
  for lado in a b; do
    if [ "$(cat "$OUT/$lado.rc")" != 0 ]; then
      echo "**$lado errors**"; echo '```'
      grep -E 'error|undefined reference' "$OUT/$lado.log" | sed -E 's#:[0-9]+:[0-9]+:#:#' | sort -u | head -n 40 | cut -c1-300
      echo '```'
    fi
  done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$rb" = 0 ] || [ "$ra" != 0 ] || exit 1
[ "$rb" = 0 ] || echo "::warning::Linux build fails on the base too"
