#!/bin/sh
# Stamped RELEASE install (task 21) — the app UNTETHERED.
#
# iOS 14+ refuses to launch a DEBUG Flutter app from the home screen, so the
# default flow (device-run.sh, hot reload) can only run while tethered to this
# terminal. That makes real multi-hour dogfooding (P1 wall-clock testing)
# impossible. This builds RELEASE mode with the SAME build stamp (sha shows in
# Settings), installs to the connected iPhone, and launches it.
#
#   ./tool/device-install.sh              # build release + install + launch
#   ./tool/device-install.sh -d <id>     # extra args pass through (e.g. pick device)
#
# WHEN IT'S RUNNING: press  q  to detach. The app STAYS on the phone and launches
# on its own from the home screen — no cable, no terminal. (`flutter install`
# can't carry the --dart-define build stamp, so we build+install via `flutter run
# --release`, which does; detaching leaves the standalone release build behind.)
#
# FREE (personal-team) SIGNING EXPIRES AFTER 7 DAYS: when the icon greys out or
# iOS says "unavailable", just re-run this to recertify — same command.
#
# Debug hot-reload workflow is unchanged: keep using ./tool/device-run.sh.
set -e
cd "$(dirname "$0")/.."
SHA=$(git rev-parse --short HEAD)
git diff --quiet && git diff --cached --quiet || SHA="$SHA+dirty"
N=$(git rev-list --count HEAD)
echo "WERKZ RELEASE install — build B$N · $SHA  (press q to detach → runs standalone)"
exec flutter run --release \
  --dart-define=WERKZ_GIT_SHA="$SHA" \
  --dart-define=WERKZ_BUILD_NO="$N" \
  "$@"
