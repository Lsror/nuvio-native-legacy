#!/bin/bash
# Pre-PR check, best effort: the Android debug build (tools/android.sh
# --debug-only, no P2P engine, no prebuilt curl) and the Kotlin unit tests, on
# the base (./a) and on the branch (./b). A failure on both sides is this
# runner's setup, not the branch.
#   bash android.sh      (after trees.sh; run from the directory holding a/ b/)
set -uo pipefail
RAIZ=$PWD
OUT=$RAIZ/out-android; mkdir -p "$OUT"
for lado in a b; do
  ( cd "$RAIZ/$lado" && NUVIO_P2P_MOTOR=none NUVIO_SEM_CURL=1 bash tools/android.sh --debug-only > "$OUT/$lado.build.log" 2>&1 ); echo $? > "$OUT/$lado.build.rc"
  ls -l "$RAIZ/$lado"/build/android/*.apk > "$OUT/$lado.apk.txt" 2>/dev/null
  ( cd "$RAIZ/$lado/android" && timeout 1500 ./gradlew --no-daemon testDebugUnitTest > "$OUT/$lado.unit.log" 2>&1 ); echo $? > "$OUT/$lado.unit.rc"
done
{
  echo "### Android (best effort): debug build and Kotlin unit tests"
  for lado in a b; do
    nome=base; [ "$lado" = b ] && nome=branch
    echo "- $nome: build exit $(cat "$OUT/$lado.build.rc"), unit tests exit $(cat "$OUT/$lado.unit.rc")"
    if [ -s "$OUT/$lado.apk.txt" ]; then echo '```'; awk '{print $5, $NF}' "$OUT/$lado.apk.txt"; echo '```'; fi
    for k in build unit; do
      if [ "$(cat "$OUT/$lado.$k.rc")" != 0 ]; then
        echo "$nome $k, last lines:"; echo '```'
        grep -E 'error|ERRO|FAILED|falta|ausente|Exception|e: ' "$OUT/$lado.$k.log" | sed -E 's#:[0-9]+:[0-9]+:#:#' | sort -u | head -n 25 | cut -c1-300
        tail -n 6 "$OUT/$lado.$k.log" | cut -c1-300
        echo '```'
      fi
    done
  done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
for k in build unit; do
  [ "$(cat "$OUT/b.$k.rc")" = 0 ] || [ "$(cat "$OUT/a.$k.rc")" != 0 ] || exit 1
done
exit 0
