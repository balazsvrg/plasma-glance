#!/usr/bin/env bash
# Install or upgrade the widget for the current user (no root needed).
set -euo pipefail

cd "$(dirname "$0")"

SRC="glance"
# The plugin ID lives in one place: the widget's metadata.json.
ID=$(python3 -c "import json; print(json.load(open('$SRC/metadata.json'))['KPlugin']['Id'])")
INSTALLED="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$ID"

command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found (is Plasma 6 installed?)" >&2; exit 1; }

if [ -d "$INSTALLED" ]; then
    kpackagetool6 -t Plasma/Applet -u "$SRC"
else
    kpackagetool6 -t Plasma/Applet -i "$SRC"
fi

echo
echo "Installed. To load the new version, reload Plasma:"
echo "  kquitapp6 plasmashell; kstart plasmashell"
echo "Then right-click the panel > Add Widgets > 'Glance'."
