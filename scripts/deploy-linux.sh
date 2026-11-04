#!/bin/sh
# Standard Linux deploy: compiles the release, installs it and registers it in
# the app launcher of this computer. Run this again to update. The data stays
# apart: ~/Documents/aupp holds the database, so never install there.
#
# Optional private/build.env sets AUPP_INSTALL_DIR and AUPP_BUILD_ARGS.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
stage="$root/build/aupp-deploy"

cd "$root"
scripts/link-private.sh
AUPP_BUILD_ARGS=""
[ -f private/build.env ] && . private/build.env
# The SEC asks automated clients for a contact (Análise of stocks abroad).
if [ -f private/sec_contact ]; then
  AUPP_BUILD_ARGS="$AUPP_BUILD_ARGS --dart-define=SEC_CONTACT=$(tr -d '[:space:]' < private/sec_contact)"
fi
app="${AUPP_INSTALL_DIR:-$HOME/.local/opt/aupp}"
if ! pkg-config --exists webkit2gtk-4.1; then
  echo "Aviso: sem webkit2gtk-4.1, os sites abrem no navegador." >&2
  echo "Para abrir dentro do app: sudo pacman -S webkit2gtk-4.1" >&2
fi
# shellcheck disable=SC2086
flutter build linux --release $AUPP_BUILD_ARGS

# Stage outside the install folder: a folder sync never sees a half copy, and a
# failed copy leaves the installed app as it was. Keeping the times spares it
# from sending files that did not change.
rm -rf "$stage"
cp -a build/linux/x64/release/bundle "$stage"
cp linux/assets/aupp.png "$stage/aupp.png"
cp scripts/register-linux.sh "$stage/registrar.sh"
chmod +x "$stage/registrar.sh" "$stage/aupp"
mkdir -p "$(dirname "$app")"
# Everything above runs with the app open; only replacing its files waits.
if pgrep -x aupp >/dev/null; then
  echo "Compilado. Feche o app para instalar."
  while pgrep -x aupp >/dev/null; do sleep 2; done
fi
rm -rf "$app"
mv "$stage" "$app"

"$app/registrar.sh"
echo "Instalado em $app"
