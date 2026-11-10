#!/usr/bin/env bash
# Build dist/<id>-<version>.plasmoid: a zip with metadata.json and contents/ at its top level.
# Install it with:  kpackagetool6 -t Plasma/Applet -i dist/<file>.plasmoid
# (or from Plasma: right-click the panel > Add Widgets > Get New Widgets > Install from Local File).
set -euo pipefail

cd "$(dirname "$0")"

SRC="glance"
ID=$(python3 -c "import json; print(json.load(open('$SRC/metadata.json'))['KPlugin']['Id'])")
VERSION=$(python3 -c "import json; print(json.load(open('$SRC/metadata.json'))['KPlugin']['Version'])")
OUT="dist/$ID-$VERSION.plasmoid"

command -v zip >/dev/null || { echo "zip not found" >&2; exit 1; }

mkdir -p dist
rm -f "$OUT"
# -X: no extra file attributes, so the archive is reproducible; -r: recurse.
(cd "$SRC" && zip -q -X -r "../$OUT" metadata.json contents)

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
unzip -l "$OUT" | tail -n +4 | head -n -2 | awk '{print "  " $4}'
