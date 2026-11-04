#!/bin/bash
# Writes the source that may be published to an empty folder: what git tracks
# or would add, nothing ignored. The lock file and the plugin registrants are
# regenerated there, so nothing from private/ remains in them.
set -eu
dest=${1:?usage: scripts/export-public.sh <empty folder>}
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
cd "$(dirname "$0")/.."
root=$PWD
if [ -n "$(ls -A "$dest")" ]; then
  echo "$dest is not empty" >&2
  exit 1
fi
files=()
while IFS= read -r -d '' file; do
  if [ -f "$file" ]; then files+=("$file"); fi
done < <(git ls-files -co --exclude-standard -z)
tar -cf - -- "${files[@]}" | tar -xf - -C "$dest"
(cd "$dest" && flutter pub get)
"$root/scripts/check-public.sh" "${files[@]/#/$dest/}"
echo "Exported to $dest"
