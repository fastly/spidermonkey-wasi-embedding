#!/usr/bin/env bash

set -euo pipefail
set -x

if [ $# -lt 1 ]; then
    echo "Usage: build.sh {release|debug} [{normal|weval}] [rebuild]"
    exit 1
fi

if [ $# -eq 1 ]; then
    $0 $1 normal
    $0 $1 weval
    exit 0
fi

if [ $# -eq 3 ]; then
    rebuild=1
else
    rebuild=0
fi

working_dir="$(pwd)"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Add fake wasm-opt to PATH.
export PATH=$script_dir/fake-bin:$PATH

# Mode: release or debug
mode=$1
# Variant: normal or weval
variant=$2
mozconfig="${working_dir}/mozconfig-${mode}-${variant}"
objdir="obj-$mode-$variant"
outdir="$mode-$variant"

cat $script_dir/mozconfig.defaults > "$mozconfig"
cat << EOF >> "$mozconfig"
ac_add_options --prefix=${working_dir}/${objdir}/dist
mk_add_options MOZ_OBJDIR=${working_dir}/${objdir}
mk_add_options AUTOCLOBBER=1
EOF

if [ "$variant" == "weval" ]; then
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

if [ $rebuild -eq 0 ]; then
    # Ensure the Rust version matches that used by Gecko, and can compile to WASI
    rustup target add wasm32-wasi

    fetch_commits=
    if [[ ! -a gecko-dev ]]; then

      # Clone Gecko repository at the required revision
      mkdir gecko-dev

      git -C gecko-dev init
      git -C gecko-dev remote add --no-tags -t wasi-embedding \
        origin "$(cat "$script_dir/gecko-repository")"

      fetch_commits=1
    fi

    target_rev="$(cat "$script_dir/gecko-revision")"
    if [[ -n "$fetch_commits" ]] || \
      [[ "$(git -C gecko-dev rev-parse HEAD)" != "$target_rev" ]]; then
      git -C gecko-dev fetch --depth 1 origin "$target_rev"
      git -C gecko-dev checkout FETCH_HEAD
    fi

    # Use Gecko's build system bootstrapping to ensure all dependencies are
    # installed
    cd gecko-dev
    ./mach --no-interactive bootstrap --application-choice=js --no-system-changes

    # ... except, that doesn't install the wasi-sysroot, which we need, so we do
    # that manually.
    cd ~/.mozbuild
    python3 \
      "${working_dir}/gecko-dev/mach" \
      --no-interactive \
      artifact \
      toolchain \
      --bootstrap \
      --from-build \
      sysroot-wasm32-wasi
fi

cd "$working_dir"

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
