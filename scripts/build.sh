#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" dist
build_options=(--product Clippy -c release --build-system native --cache-path "$project_dir/.build/cache" --manifest-cache local -Xswiftc -gnone "$@")
swift build "${build_options[@]}"
binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
app_dir="$project_dir/dist/Clippy.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Clippy" "$app_dir/Contents/MacOS/Clippy"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/make-icon.swift "$app_dir/Contents/Resources/AppIcon.icns"
signing_identity="${CLIPPY_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - --identifier app.clippy.clipboard "$app_dir"
else
    codesign --force --sign "$signing_identity" --options runtime --timestamp --identifier app.clippy.clipboard "$app_dir"
fi
codesign --verify --strict "$app_dir"
print "Built: $app_dir"
