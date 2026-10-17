#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
COMMAND="${1:-build}"
case "$COMMAND" in
  build|test|run) shift "$(( $# > 0 ? 1 : 0 ))" ;;
  *) echo "Usage: $0 {build|test|run} [SwiftPM options...]" >&2; exit 2 ;;
esac

# Select a complete Xcode for this command only; never change global xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  SELECTED_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$SELECTED_DEVELOPER_DIR" == */CommandLineTools ]]; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
      if [[ -d "$candidate" ]]; then
        export DEVELOPER_DIR="$candidate"
        break
      fi
    done
  fi
fi

# Keep generated files outside synced checkouts and isolate simultaneous worktrees.
CHECKOUT_ID="$(printf '%s' "$ROOT_DIR" | shasum -a 256 | awk '{print substr($1,1,16)}')"
SCRATCH_PATH="${OMU_BUILD_PATH:-${HOME}/Library/Caches/OhMyUsage/Builds/$CHECKOUT_ID}"
OPTIONS=(--scratch-path "$SCRATCH_PATH")
if [[ -n "${SWIFT_BUILD_SYSTEM:-}" ]]; then
  OPTIONS+=(--build-system "$SWIFT_BUILD_SYSTEM")
fi
cd "$ROOT_DIR"
exec swift "$COMMAND" "${OPTIONS[@]}" "$@"
