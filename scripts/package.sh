#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
./scripts/build.sh "$@"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Clippy.app/Contents/Info.plist)"
architecture="$(lipo -archs dist/Clippy.app/Contents/MacOS/Clippy | tr ' ' '-')"
archive="Clippy-${version}-${architecture}.zip"
cd dist
ditto -c -k --sequesterRsrc --keepParent Clippy.app "$archive"
shasum -a 256 "$archive" > "${archive}.sha256"
print "Packaged: $project_dir/dist/$archive"
