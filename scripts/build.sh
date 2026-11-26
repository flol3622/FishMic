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

minimum_version="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")"
xcrun swiftc -target "$(uname -m)-apple-macosx$minimum_version" \
    -parse-as-library -Osize -whole-module-optimization -o "$app/Contents/MacOS/FishMic" \
    "$project_dir"/Sources/*.swift
codesign --force --sign - "$app"
codesign --verify --strict "$app"

rm -rf "$dist_dir/$app_name"
mv "$app" "$dist_dir/$app_name"
printf 'Built %s\n' "$dist_dir/$app_name"
