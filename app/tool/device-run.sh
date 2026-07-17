#!/bin/sh
# Stamped device run (task 17 B). Injects the git short-sha and a monotonically
# increasing build number (commit count) so Settings and the onboarding corner
# always answer "which build am I running?". A dirty working tree is marked.
#
#   ./tool/device-run.sh              # flutter run, stamped
#   ./tool/device-run.sh --release    # extra args pass through
set -e
cd "$(dirname "$0")/.."
SHA=$(git rev-parse --short HEAD)
git diff --quiet && git diff --cached --quiet || SHA="$SHA+dirty"
N=$(git rev-list --count HEAD)
echo "WERKZ device run — build B$N · $SHA"
exec flutter run \
  --dart-define=WERKZ_GIT_SHA="$SHA" \
  --dart-define=WERKZ_BUILD_NO="$N" \
  "$@"
