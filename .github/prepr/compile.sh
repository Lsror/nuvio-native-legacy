#!/bin/bash
# Pre-PR check: every C file of the app, syntax-checked for every platform's
# defines with the errors newer compilers make fatal, on the branch (./b) and
# on its base (./a). Only errors the branch adds are reported. This is not a
# build: SDK headers a host does not have fail the same way on both sides.
#   bash compile.sh       (after trees.sh; run from the directory holding a/ b/)
set -uo pipefail
RAIZ=$PWD
OUT=$RAIZ/out-compile; mkdir -p "$OUT"
CC=${PREPR_CC:-gcc-14}
RIGOR="-Werror=implicit-function-declaration -Werror=int-conversion -Werror=incompatible-pointer-types"
INC="-Isrc $(pkg-config --cflags sdl2 SDL2_image SDL2_ttf glesv2 egl zlib libcurl libass freetype2 fribidi harfbuzz libavformat libavcodec libavutil libswresample 2>/dev/null)"
JNI=""
if [ -n "${JAVA_HOME:-}" ]; then JNI="-I$JAVA_HOME/include -I$JAVA_HOME/include/linux"; fi

conjunto() { # name -> defines
  case "$1" in
    linux)    echo "-DNV_LINUX_DESKTOP" ;;
    tpk)      echo "-DNV_TPK -DNV_ASS_LIBASS -include src/tpk.h" ;;
    tpk-dts)  echo "-DNV_TPK -DNV_DTS_FFMPEG -DNV_ASS_LIBASS -include src/tpk.h" ;;
    tpk40)    echo "-DNV_TPK -DNV_TPK40 -DNV_ASS_LIBASS -include src/tpk.h" ;;
    webos)    echo "-DNV_WEBOS -DNV_ASS_LIBASS -DNV_DTS_FFMPEG -DNV_DTS_WEBOS_RECOVERY" ;;
    android)  echo "-DNV_ANDROID $JNI" ;;
    vidaa)    echo "-DNV_VIDAA" ;;
  esac
}
um() { # um <side> <set> <file>: error lines, without line numbers
  local lado=$1 c=$2 f=$3
  ( cd "$RAIZ/$lado" && $CC -fsyntax-only -w $RIGOR $INC $(conjunto "$c") "$f" 2>&1 ) \
    | grep -E '(error|fatal error):' | sed -E 's#^([^:]+):[0-9]+:[0-9]+:#\1:#' | sort -u
}
export -f um conjunto; export RAIZ CC RIGOR INC JNI
falhou=0
{
echo "### Strict syntax check per platform ($($CC --version | head -1)): errors the branch adds"
for c in linux tpk tpk-dts tpk40 webos android vidaa; do
  for lado in a b; do
    ( cd "$RAIZ/$lado" && ls src/*.c src/dts/*.c ) \
      | xargs -P "${PREPR_JOBS:-4}" -I{} bash -c 'um "$0" "$1" "$2"' "$lado" "$c" {} | sort -u > "$OUT/$c.$lado.txt"
  done
  comm -13 "$OUT/$c.a.txt" "$OUT/$c.b.txt" > "$OUT/$c.novo.txt"
  na=$(wc -l < "$OUT/$c.a.txt"); nb=$(wc -l < "$OUT/$c.b.txt"); nn=$(wc -l < "$OUT/$c.novo.txt")
  echo "- **$c**: base $na error lines, branch $nb, new on the branch **$nn**"
  if [ "$nn" -gt 0 ]; then
    echo '```'; head -n 60 "$OUT/$c.novo.txt" | cut -c1-300; echo '```'
    grep -v 'fatal error:.*No such file' "$OUT/$c.novo.txt" | grep -q . && falhou=1
  fi
done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
# the subshell above cannot set falhou here; decide again from the files
for f in "$OUT"/*.novo.txt; do grep -v 'fatal error:.*No such file' "$f" | grep -q . && falhou=1; done
exit $falhou
