#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${CHROMIUM_WORK_DIR:-$ROOT_DIR/.chromium-ci}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$WORK_DIR/depot_tools}"
SRC_DIR="$WORK_DIR/src"
PATCH_DIR="$ROOT_DIR/patches"
CHROMIUM_REF="${CHROMIUM_REF:-origin/main}"
BUILD_MODE="${BUILD_MODE:-apply-only}" # apply-only|minimal|full
VERIFY_TARGET="${VERIFY_TARGET:-chrome/common:common}"
GN_OUT_DIR="${CHROMIUM_OUT_DIR:-out/Verify}"
NINJA_JOBS="${NINJA_JOBS:-6}"
INSTALL_LINUX_DEPS="${INSTALL_LINUX_DEPS:-1}"

log() {
  printf '[ci-verify] %s\n' "$*"
}

ensure_depot_tools() {
  mkdir -p "$WORK_DIR"
  if [[ ! -d "$DEPOT_TOOLS_DIR/.git" ]]; then
    log "Cloning depot_tools..."
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
  fi
  export PATH="$DEPOT_TOOLS_DIR:$PATH"
}

fetch_or_sync_chromium() {
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    log "Fetching Chromium source (no history)..."
    pushd "$WORK_DIR" >/dev/null
    fetch --nohooks --no-history chromium
    popd >/dev/null
  fi

  pushd "$SRC_DIR" >/dev/null
  log "Checking out Chromium ref: $CHROMIUM_REF"
  git fetch origin
  git checkout "$CHROMIUM_REF"
  gclient sync -D --nohooks
  popd >/dev/null
}

install_linux_build_deps() {
  if [[ "${INSTALL_LINUX_DEPS}" != "1" ]]; then
    log "Skipping Linux build deps install (INSTALL_LINUX_DEPS=$INSTALL_LINUX_DEPS)"
    return
  fi

  if [[ "$(uname -s)" != "Linux" ]]; then
    return
  fi

  pushd "$SRC_DIR" >/dev/null
  if [[ -x "build/install-build-deps.sh" ]]; then
    log "Installing Linux build dependencies..."
    sudo build/install-build-deps.sh --no-prompt --no-chromeos-fonts
  else
    log "build/install-build-deps.sh not found, skipping"
  fi
  popd >/dev/null
}

collect_patches() {
  PATCHES=()
  while IFS= read -r -d '' patch; do
    PATCHES+=("$patch")
  done < <(find "$PATCH_DIR" -maxdepth 1 -name "*.patch" -print0 | sort -z)
}

apply_patches() {
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    log "Missing Chromium source: $SRC_DIR"
    exit 2
  fi

  collect_patches
  if [[ ${#PATCHES[@]} -eq 0 ]]; then
    log "No patches found in $PATCH_DIR"
    return
  fi

  pushd "$SRC_DIR" >/dev/null
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "Chromium tree is dirty before apply; abort."
    git status --short
    exit 3
  fi

  for patch in "${PATCHES[@]}"; do
    log "Checking patch: $patch"
    git apply --check "$patch"
    log "Applying patch: $patch"
    git apply --3way "$patch"
  done
  popd >/dev/null
}

resolve_target_cpu() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    arm64|aarch64)
      echo "arm64"
      ;;
    *)
      echo "x64"
      ;;
  esac
}

compile_verify() {
  local cpu gn_args
  cpu="$(resolve_target_cpu)"
  gn_args="is_debug=false symbol_level=0 use_debug_fission=false is_component_build=true target_cpu=\"$cpu\""

  pushd "$SRC_DIR" >/dev/null
  log "Generating GN files in $GN_OUT_DIR"
  gn gen "$GN_OUT_DIR" --args="$gn_args"

  if [[ "$BUILD_MODE" == "minimal" ]]; then
    log "Running minimal compile target: $VERIFY_TARGET (jobs=$NINJA_JOBS)"
    autoninja -C "$GN_OUT_DIR" -j "$NINJA_JOBS" "$VERIFY_TARGET"
  elif [[ "$BUILD_MODE" == "full" ]]; then
    log "Running full compile target: chrome (jobs=$NINJA_JOBS)"
    autoninja -C "$GN_OUT_DIR" -j "$NINJA_JOBS" chrome
  else
    log "Unknown BUILD_MODE: $BUILD_MODE"
    exit 4
  fi
  popd >/dev/null
}

main() {
  log "Mode=$BUILD_MODE, Ref=$CHROMIUM_REF, WorkDir=$WORK_DIR"
  df -h || true
  ensure_depot_tools
  fetch_or_sync_chromium
  apply_patches

  if [[ "$BUILD_MODE" == "apply-only" ]]; then
    log "Patch apply check finished."
    exit 0
  fi

  install_linux_build_deps
  compile_verify
  log "Compile verification finished."
}

main "$@"

