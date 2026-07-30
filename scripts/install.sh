#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$("$project_dir/scripts/build-app.sh")"
destination="$HOME/Applications/AeroPeek.app"

mkdir -p "$HOME/Applications"
ditto "$app_dir" "$destination"

echo "Installed to $destination"
echo "Open AeroPeek, then hold Control–Option–Space to show the overview."
