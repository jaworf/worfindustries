#!/bin/zsh

set -eu

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$developer_dir" ]]; then
    developer_dir="$(/usr/bin/xcode-select -p)"
fi
real_clang="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"

is_preprocessor_probe=false
requests_macro_dump=false
for argument in "$@"; do
    [[ "$argument" == "-E" ]] && is_preprocessor_probe=true
    [[ "$argument" == "-dM" ]] && requests_macro_dump=true
done

if $is_preprocessor_probe && $requests_macro_dump; then
    filtered_arguments=()
    for argument in "$@"; do
        [[ "$argument" == "-v" ]] || filtered_arguments+=("$argument")
    done
    exec "$real_clang" "${filtered_arguments[@]}"
fi

exec "$real_clang" "$@"
