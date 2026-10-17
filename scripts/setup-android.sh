#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$project_dir/tools"
download_dir="$tools_dir/downloads"
template_dir="$tools_dir/godot-data/godot/export_templates/4.6.stable"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo "This installer supports Linux x86_64." >&2
    exit 1
fi
for dependency in curl unzip tar; do
    command -v "$dependency" >/dev/null || { echo "Install $dependency first." >&2; exit 1; }
done
mkdir -p "$download_dir" "$tools_dir/config" "$template_dir"

download() {
    local url="$1" destination="$2"
    if [[ ! -f "$destination" ]]; then
        curl --fail --location --retry 3 --output "$destination.part" "$url"
        mv "$destination.part" "$destination"
    fi
}

if [[ ! -x "$tools_dir/jdk-17/bin/java" ]]; then
    archive="$download_dir/temurin-jdk-17.tar.gz"
    download 'https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse' "$archive"
    mkdir -p "$tools_dir/jdk-17"
    tar -xzf "$archive" --strip-components=1 -C "$tools_dir/jdk-17"
fi

if [[ ! -x "$tools_dir/android-sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
    archive="$download_dir/commandlinetools-linux-13114758_latest.zip"
    download 'https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip' "$archive"
    staging_dir="$(mktemp -d "$download_dir/sdk.XXXXXX")"
    unzip -q "$archive" -d "$staging_dir"
    mkdir -p "$tools_dir/android-sdk/cmdline-tools"
    mv "$staging_dir/cmdline-tools" "$tools_dir/android-sdk/cmdline-tools/latest"
    rmdir "$staging_dir"
fi

export JAVA_HOME="$tools_dir/jdk-17"
export ANDROID_HOME="$tools_dir/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Show the SDK license prompts; preserve sdkmanager's failure status.
sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" 'platform-tools' 'build-tools;35.0.1' 'platforms;android-35'

if [[ ! -f "$template_dir/android_debug.apk" || ! -f "$template_dir/android_release.apk" ]]; then
    archive="$download_dir/Godot_v4.6-stable_export_templates.tpz"
    download 'https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_export_templates.tpz' "$archive"
    unzip -jo "$archive" 'templates/android_debug.apk' 'templates/android_release.apk' -d "$template_dir"
fi

if [[ ! -f "$tools_dir/config/debug.keystore" ]]; then
    keytool -genkeypair -keystore "$tools_dir/config/debug.keystore" \
        -storepass android -alias androiddebugkey -keypass android \
        -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
    chmod 600 "$tools_dir/config/debug.keystore"
fi

"$project_dir/godot.sh" --headless --editor --script res://scripts/configure_android.gd
echo 'Android setup complete. Open the editor with ./godot.sh.'
