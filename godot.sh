#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_binary="$project_dir/tools/godot/Godot_v4.6-stable_linux.x86_64"

if [[ ! -x "$godot_binary" ]]; then
    printf 'Godot is missing: %s\n' "$godot_binary" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    set -- --editor
fi

exec "$godot_binary" --path "$project_dir" "$@"
