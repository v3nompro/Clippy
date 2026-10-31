#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
swift run --build-system native --cache-path "$project_dir/.build/cache" --manifest-cache local "$@" ClippyChecks
