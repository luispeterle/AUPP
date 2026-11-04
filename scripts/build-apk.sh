#!/bin/sh
# Release APK. Optional private/build.env sets AUPP_BUILD_ARGS.
set -eu
cd "$(dirname "$0")/.."
scripts/link-private.sh
AUPP_BUILD_ARGS=""
[ -f private/build.env ] && . private/build.env
# The SEC asks automated clients for a contact (Análise of stocks abroad).
if [ -f private/sec_contact ]; then
  AUPP_BUILD_ARGS="$AUPP_BUILD_ARGS --dart-define=SEC_CONTACT=$(tr -d '[:space:]' < private/sec_contact)"
fi
# shellcheck disable=SC2086
flutter build apk --release $AUPP_BUILD_ARGS
