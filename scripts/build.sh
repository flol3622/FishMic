#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
dist_dir="$project_dir/dist"
app_name="FishMic.app"

mkdir -p "$dist_dir"
build_dir="$(mktemp -d "$dist_dir/.build.XXXXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
app="$build_dir/$app_name"
mkdir -p "$app/Contents/MacOS"
cp "$project_dir/app/Info.plist" "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp "$project_dir/app/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# MP3 export uses LAME. Homebrew's formula passes its path; a local build asks Homebrew.
lame_prefix="${LAME_PREFIX:-$(brew --prefix lame 2>/dev/null || true)}"
if [[ ! -f "$lame_prefix/include/lame/lame.h" ]]; then
    printf 'FishMic needs the LAME MP3 encoder: brew install lame\n' >&2
    exit 1
fi

minimum_version="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")"
xcrun swiftc -target "$(uname -m)-apple-macosx$minimum_version" \
    -parse-as-library -Osize -whole-module-optimization -o "$app/Contents/MacOS/FishMic" \
    -import-objc-header "$project_dir/Sources/Lame.h" -Xcc -I"$lame_prefix/include" \
    -L"$lame_prefix/lib" -lmp3lame \
    "$project_dir"/Sources/*.swift
codesign --force --sign - "$app"
codesign --verify --strict "$app"

rm -rf "$dist_dir/$app_name"
mv "$app" "$dist_dir/$app_name"
printf 'Built %s\n' "$dist_dir/$app_name"
