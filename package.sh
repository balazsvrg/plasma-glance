#!/usr/bin/env bash
# Build dist/<id>-<version>.plasmoid: a zip with metadata.json and contents/ at its top level.
# Install it with:  kpackagetool6 -t Plasma/Applet -i dist/<file>.plasmoid
# (or from Plasma: right-click the panel > Add Widgets > Get New Widgets > Install from Local File).
set -euo pipefail

cd "$(dirname "$0")"

SRC="glance"
read -r ID VERSION < <(python3 -c "import json; k = json.load(open('$SRC/metadata.json'))['KPlugin']; print(k['Id'], k['Version'])")
OUT="dist/$ID-$VERSION.plasmoid"

for tool in zip unzip du; do
    command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done

mkdir -p dist
rm -f "$OUT"
# -X: leave out extra file attributes (uid/gid, extended timestamps); file mtimes are still stored, so
# the archive is not byte-for-byte reproducible. -r: recurse. It zips the working tree, not a git commit.
(cd "$SRC" && zip -q -X -r "../$OUT" metadata.json contents)

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
unzip -l "$OUT" | tail -n +4 | head -n -2 | awk '{print "  " $4}'
