#!/bin/sh
# Registers the app that sits next to this script in the launcher, for this
# user only. The deploy copies it next to the app as registrar.sh: if a folder
# sync takes the app to other computers, each one has its own launcher, so run
# it once on each. Updates after that need nothing.
set -eu
app=$(cd "$(dirname "$0")" && pwd)
apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor/256x256/apps"

if ! ldconfig -p 2>/dev/null | grep -q 'libwebkit2gtk-4.1'; then
  echo "Aviso: sem webkit2gtk-4.1 o app não abre. Instale: sudo pacman -S webkit2gtk-4.1" >&2
fi

chmod +x "$app/aupp"
mkdir -p "$apps" "$icons"
# Left by the app's old name.
rm -f "$apps/com.github.emavgl.oinkoin.desktop" "$icons/oinkoin.png"
cp "$app/aupp.png" "$icons/aupp.png"
# The launcher points at the file itself: a panel already running does not see
# icons added to the theme after it started, and shows a blank one.
cat > "$apps/app.aupp.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=AUPP
GenericName=Controle financeiro
Comment=Lançamentos, orçamento e investimentos
Exec="$app/aupp"
Path=$app
Icon=$app/aupp.png
Terminal=false
Categories=Office;Finance;
Keywords=finanças;gastos;orçamento;aupp;
StartupNotify=true
StartupWMClass=app.aupp
DESKTOP

if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$apps" || true
fi
# KDE reads the launcher from its own cache.
if command -v kbuildsycoca6 >/dev/null; then
  kbuildsycoca6 >/dev/null 2>&1 || true
fi
echo "Registrado no lançador: $app"
