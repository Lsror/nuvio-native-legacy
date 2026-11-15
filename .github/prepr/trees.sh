#!/bin/bash
# Pre-PR check: put the branch under review in ./b and its merge base with the
# target branch in ./a, and list what changed between them.
#   bash trees.sh <ref> <base>     e.g. subtitle-rewrite master
set -euo pipefail
REF=$1 BASE=$2
git clone -q --filter=blob:none --no-checkout "https://github.com/$GITHUB_REPOSITORY" b
cd b
git checkout -q --detach "origin/$REF"
MB=$(git merge-base HEAD "origin/$BASE")
git worktree add -q --detach ../a "$MB"
git diff --name-only "$MB" HEAD > ../changed.txt
echo "branch $REF @ $(git rev-parse --short HEAD), base $BASE @ $(git rev-parse --short "$MB"), $(wc -l < ../changed.txt) files changed"
{
  echo "### Pre-PR check"
  echo "- branch: \`$REF\` @ \`$(git rev-parse --short HEAD)\`"
  echo "- base: \`$BASE\` @ \`$(git rev-parse --short "$MB")\` (merge base)"
  echo "- files changed: $(wc -l < ../changed.txt)"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
