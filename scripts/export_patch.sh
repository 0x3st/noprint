#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT_DIR/patches"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <chromium_src_dir> <commit-ish> <output_patch_name>"
  echo "Example: $0 .chromium/src HEAD 0002-load-antidetect-config.patch"
  exit 1
fi

src_dir="$1"
commit="$2"
output_name="$3"

if [[ ! -d "$src_dir/.git" ]]; then
  echo "Not a git repository: $src_dir"
  exit 2
fi

mkdir -p "$PATCH_DIR"
if [[ "$output_name" = /* ]]; then
  out_path="$output_name"
else
  out_path="$PATCH_DIR/$output_name"
fi

git -C "$src_dir" rev-parse --verify "$commit" >/dev/null
git -C "$src_dir" format-patch --stdout -1 "$commit" >"$out_path"

echo "Exported patch: $out_path"

