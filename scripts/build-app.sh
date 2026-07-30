#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/.build/AeroPeek.app"

cd "$project_dir"
swift build -c release >&2

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/AeroPeek" "$app_dir/Contents/MacOS/AeroPeek"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir" >&2

echo "$app_dir"
