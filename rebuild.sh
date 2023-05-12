#!/usr/bin/env bash

set -euo pipefail
set -x

if [ $# -lt 3 ]; then
    echo "Usage: rebuild.sh {release|debug} {normal|weval}"
    exit 1
fi

working_dir="$(pwd)"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

mode=$1
variant=$2
mozconfig="${working_dir}/mozconfig-${mode}"
objdir="obj-$mode-$variant"
outdir="$mode-$variant"

cat $script_dir/mozconfig.defaults > "$mozconfig"
cat << EOF >> "$mozconfig"
ac_add_options --prefix=${working_dir}/${objdir}/dist
mk_add_options MOZ_OBJDIR=${working_dir}/${objdir}
mk_add_options AUTOCLOBBER=1
EOF

if [ "$mode" == "weval" ]; then
    cat $script_dir/mozconfig.weval >> "$mozconfig"
fi

target="$(uname)"
case "$target" in
  Linux)
    echo "ac_add_options --disable-stdcxx-compat" >> "$mozconfig"
    ;;

  Darwin)
    echo "ac_add_options --host=aarch64-apple-darwin" >> "$mozconfig"
    ;;

  *)
    echo "Unsupported build target: $target"
    exit 1
    ;;
esac

case "$mode" in
  release)
    echo "ac_add_options --disable-debug" >> "$mozconfig"
    ;;

  debug)
    echo "ac_add_options --enable-debug" >> "$mozconfig"
    ;;

  *)
    echo "Unknown build type: $mode"
    exit 1
    ;;
esac

# Build SpiderMonkey for WASI
MOZCONFIG="${mozconfig}" \
MOZ_FETCHES_DIR=~/.mozbuild \
CC=~/.mozbuild/clang/bin/clang \
  python3 "${working_dir}/gecko-dev/mach" \
  --no-interactive \
    build

# Copy header, object, and static lib files
rm -rf "$outdir"
mkdir -p "$outdir/lib"

cd "$objdir"
cp -Lr dist/include "../$outdir"

while read -r file; do
  cp "$file" "../$outdir/lib"
done < "$script_dir/object-files.list"

cp js/src/build/libjs_static.a "wasm32-wasi/${mode}/libjsrust.a" "../$outdir/lib"
