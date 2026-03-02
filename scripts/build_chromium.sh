#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${CHROMIUM_WORK_DIR:-$ROOT_DIR/.chromium}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$WORK_DIR/depot_tools}"
SRC_DIR="$WORK_DIR/src"
PATCH_DIR="$ROOT_DIR/patches"
CHROMIUM_REF="${CHROMIUM_REF:-origin/main}"
OUT_DIR="${CHROMIUM_OUT_DIR:-out/Default}"

if [[ ! -d "$DEPOT_TOOLS_DIR" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
fi

export PATH="$DEPOT_TOOLS_DIR:$PATH"
mkdir -p "$WORK_DIR"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  pushd "$WORK_DIR" >/dev/null
  fetch --nohooks chromium
  popd >/dev/null
fi

pushd "$SRC_DIR" >/dev/null
git fetch origin
git checkout "$CHROMIUM_REF"
gclient sync -D

PATCHES=()
while IFS= read -r -d '' patch; do
  PATCHES+=("$patch")
done < <(find "$PATCH_DIR" -maxdepth 1 -name "*.patch" -print0 | sort -z)

if [[ ${#PATCHES[@]} -gt 0 ]]; then
  for patch in "${PATCHES[@]}"; do
    echo "Applying patch: $patch"
    git apply --3way "$patch"
  done
else
  echo "No patches found in $PATCH_DIR (*.patch), continue with clean Chromium."
fi

gn gen "$OUT_DIR" --args='is_debug=false symbol_level=0 target_cpu="arm64"'
ninja -C "$OUT_DIR" chrome
popd >/dev/null

echo
echo "Build complete:"
echo "  $SRC_DIR/$OUT_DIR/chrome"

