#!/usr/bin/env bash
# Remove the widget for the current user. Remove it from your panels first.
set -euo pipefail

ID="org.local.cpumemtemp"

kpackagetool6 -t Plasma/Applet -r "$ID"
echo "Removed. Reload Plasma to finish: kquitapp6 plasmashell; kstart plasmashell"
