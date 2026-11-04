#!/bin/sh
# Fails if the given files (default: everything git would publish) contain a
# word from private/public-check-patterns.txt. No patterns file, no check.
# CONTRIBUTORS and the contributors pages name people on purpose.
set -eu
cd "$(dirname "$0")/.."
patterns=private/public-check-patterns.txt
[ -f "$patterns" ] || exit 0

if [ $# -eq 0 ]; then
  set -- $(git ls-files -co --exclude-standard)
fi
found=0
for file in "$@"; do
  [ -f "$file" ] || continue
  case "$file" in
    CONTRIBUTORS|*/CONTRIBUTORS|*website/src/pages/contributors.astro|*lib/settings/contributors-page.dart) continue ;;
  esac
  if grep -v '^#' "$patterns" | grep -IiHnE -f - "$file"; then
    found=1
  fi
done
if [ "$found" -ne 0 ]; then
  echo "Dados pessoais nos arquivos acima (ver $patterns)." >&2
  exit 1
fi
