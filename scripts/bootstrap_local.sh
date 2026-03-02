#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$ROOT_DIR/configs/profiles"
mkdir -p "$ROOT_DIR/shared_extensions"

if [[ ! -f "$ROOT_DIR/configs/global.json" ]]; then
  cp "$ROOT_DIR/configs/global.example.json" "$ROOT_DIR/configs/global.json"
  echo "Created configs/global.json"
else
  echo "Skip existing configs/global.json"
fi

if [[ ! -f "$ROOT_DIR/configs/profiles/dev.json" ]]; then
  cp "$ROOT_DIR/configs/profiles/dev.example.json" "$ROOT_DIR/configs/profiles/dev.json"
  echo "Created configs/profiles/dev.json"
else
  echo "Skip existing configs/profiles/dev.json"
fi

echo "Bootstrap finished."

