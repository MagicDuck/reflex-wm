#!/bin/sh
set -eu
if [ "$(uname -s)" != Linux ]; then
    echo 'Build this package on Linux with Swift 6.2 or newer.' >&2
    exit 1
fi
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
swift build -c release --product reflex-wm-kde --static-swift-stdlib
bin_path=$(swift build -c release --show-bin-path)
output="$project_root/build/linux/$(uname -m)"
mkdir -p "$output/kwin" "$output/scripts"
install -m 755 "$bin_path/reflex-wm-kde" "$output/reflex-wm-kde"
cp -R Resources/kwin/reflex-wm "$output/kwin/"
cp Resources/reflex-wm.service "$output/"
install -m 755 scripts/install-linux.sh "$output/scripts/install-linux.sh"
cp README-kde.md "$output/"
archive="$project_root/build/reflex-wm-kde-linux-$(uname -m).tar.gz"
tar -czf "$archive" -C "$output" reflex-wm-kde kwin reflex-wm.service scripts README-kde.md
printf '%s\n' "$output"
