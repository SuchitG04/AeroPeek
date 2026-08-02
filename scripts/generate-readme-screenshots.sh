#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/docs/screenshots"

mkdir -p "$output_dir"
cd "$project_dir"
swift run -c release AeroPeek --render-readme-screenshots "$output_dir"

echo "$output_dir"
