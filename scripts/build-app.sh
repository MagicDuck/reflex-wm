#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="$project_root/build/reflex-wm.app"
contents_path="$app_path/Contents"
executable_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"

swift build --package-path "$project_root" -c release

if [[ "$app_path" != "$project_root/build/reflex-wm.app" ]]; then
    print -u2 "Unexpected app output path"
    exit 1
fi
rm -rf "$app_path"
mkdir -p "$executable_path" "$resources_path"
cp "$project_root/.build/release/reflex-wm" "$executable_path/reflex-wm"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/reflex-wm.icns" "$resources_path/reflex-wm.icns"

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$app_path"
plutil -lint "$contents_path/Info.plist"
codesign --verify --deep --strict "$app_path"

print "$app_path"
