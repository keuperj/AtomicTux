#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_binary="$project_dir/tools/godot/Godot_v4.6-stable_linux.x86_64"

# Keep editor configuration and Android tools local to this checkout.
export XDG_CONFIG_HOME="$project_dir/tools/config"
export XDG_DATA_HOME="$project_dir/tools/godot-data"
export XDG_CACHE_HOME="$project_dir/tools/cache"
export JAVA_HOME="$project_dir/tools/jdk-17"
export ANDROID_HOME="$project_dir/tools/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$project_dir/tools/config/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
mkdir -p "$XDG_CONFIG_HOME"

if [[ ! -x "$godot_binary" ]]; then
    printf 'Godot is missing: %s\n' "$godot_binary" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    set -- --editor
fi

exec "$godot_binary" --path "$project_dir" "$@"
