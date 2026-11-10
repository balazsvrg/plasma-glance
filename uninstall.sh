#!/usr/bin/env bash
# Remove the widget for the current user. Remove it from your panels first.
set -euo pipefail

cd "$(dirname "$0")"

# The plugin ID lives in one place: the widget's metadata.json.
ID=$(python3 -c "import json; print(json.load(open('package/metadata.json'))['KPlugin']['Id'])")

kpackagetool6 -t Plasma/Applet -r "$ID"
echo "Removed. Reload Plasma to finish: kquitapp6 plasmashell; kstart plasmashell"
