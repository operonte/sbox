#!/usr/bin/env bash
set -euo pipefail

# Compila sbox (Linux, release) y lo instala como aplicación del menú.
# Reejecutable: vuelve a correrlo tras cada cambio para actualizar el launcher.
#   ./scripts/install-linux.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"

INSTALL_DIR="$HOME/.local/opt/sbox"
APPS_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$APPS_DIR/sbox.desktop"

echo "==> Compilando sbox (Linux release)…"
cd "$APP_DIR"
flutter build linux --release

BUNDLE="$(ls -d "$APP_DIR"/build/linux/*/release/bundle 2>/dev/null | head -1)"
if [ -z "$BUNDLE" ] || [ ! -d "$BUNDLE" ]; then
  echo "ERROR: no se encontró el bundle compilado bajo $APP_DIR/build/linux" >&2
  exit 1
fi

echo "==> Instalando en $INSTALL_DIR…"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$BUNDLE"/. "$INSTALL_DIR"/

# Icono propio junto al binario (el .desktop lo referencia por ruta absoluta).
cp "$APP_DIR/assets/icon/sbox_icon.png" "$INSTALL_DIR/sbox_icon.png"

echo "==> Creando lanzador en el menú…"
mkdir -p "$APPS_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=sbox
GenericName=Portapapeles LAN
Comment=Portapapeles universal entre PC y Android por la misma WiFi
Exec=$INSTALL_DIR/sbox
Icon=$INSTALL_DIR/sbox_icon.png
Terminal=false
Categories=Utility;
StartupWMClass=sbox
Keywords=clipboard;portapapeles;sbox;lan;
EOF
chmod +x "$DESKTOP_FILE"

# Refresca la base de datos del menú (si la herramienta existe).
update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo
echo "✓ Listo. Busca «sbox» en el menú de aplicaciones."
echo "  Binario:  $INSTALL_DIR/sbox"
echo "  Lanzador: $DESKTOP_FILE"
