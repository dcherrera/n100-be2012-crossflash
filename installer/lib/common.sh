#!/usr/bin/env bash
# Shared helpers for the BE2012 → UT installer scripts.
# Source this from each step:  source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$INSTALLER_DIR/.." && pwd)"
# Kept as an alias for back-compat with anything that still says CROSSFLASH_DIR.
CROSSFLASH_DIR="$REPO_DIR"
DL_DIR="$INSTALLER_DIR/downloads"
STATE_DIR="$INSTALLER_DIR/state"

mkdir -p "$DL_DIR" "$STATE_DIR"

# Toolchain paths under the repo root, populated by 00-prep.sh.
PLATFORM_TOOLS="$REPO_DIR/host-tools/platform-tools"
EDL_VENV="$REPO_DIR/venv"
EDL_LOADER="$REPO_DIR/tools/edl/Loaders/oneplus/0000000000515192_37cf317812121fed_fhprg_opn100.bin"

export PATH="$PLATFORM_TOOLS:$EDL_VENV/bin:$PATH"

# Channel + device used end-to-end. Don't change unless you know what you're doing.
SYSIMG_BASE="https://system-image.ubports.com"
SYSIMG_CHANNEL="24.04-1.x/arm64/android9plus/daily"
SYSIMG_DEVICE="billie2"

# Pretty output ---------------------------------------------------------------
say() { printf '\033[1;36m[*]\033[0m %s\n' "$*" >&2; }
ok()  { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; exit 1; }

state_mark()  { touch "$STATE_DIR/$1.done"; }
state_done()  { [[ -f "$STATE_DIR/$1.done" ]]; }

case "$(uname -s)" in
  Darwin) HOST_OS=mac   ;;
  Linux)  HOST_OS=linux ;;
  *)      HOST_OS=unknown ;;
esac

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    case "$HOST_OS" in
      mac)   die "missing command: $1  (try: brew install $1)" ;;
      linux) die "missing command: $1  (install via your package manager)" ;;
      *)     die "missing command: $1" ;;
    esac
  fi
}

# Portable file-size — BSD stat (-f%z) on macOS, GNU stat (-c%s) on Linux.
filesize() {
  if [[ "$HOST_OS" == mac ]]; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

# Portable EDL-mode USB detection.
# On macOS: ioreg sees the device's IOUSBDevice nodes by name.
# On Linux: lsusb sees Qualcomm vendor 05c6, product 9008 for EDL.
detect_edl() {
  case "$HOST_OS" in
    mac)   ioreg -p IOUSB -l -w 0 2>/dev/null | grep -q "Qualcomm CDMA Technologies MSM" ;;
    linux) lsusb 2>/dev/null | grep -qE "05c6:9008|Qualcomm.*Mass Storage" ;;
    *)     return 1 ;;
  esac
}

# Wait until phone is in a given mode, with a humanly-named timeout.
# wait_for adb|fastboot|recovery|edl  [timeout_seconds]
wait_for() {
  local mode="$1" timeout="${2:-180}" t=0
  while (( t < timeout )); do
    case "$mode" in
      adb)      adb get-state >/dev/null 2>&1 && [[ "$(adb get-state 2>/dev/null)" == "device" ]] && return 0 ;;
      recovery) [[ "$(adb get-state 2>/dev/null || true)" == "recovery" ]] && return 0 ;;
      fastboot) fastboot devices 2>/dev/null | grep -q "fastboot" && return 0 ;;
      edl)      detect_edl && return 0 ;;
      *) die "wait_for: unknown mode $mode" ;;
    esac
    sleep 2
    ((t+=2))
  done
  die "timeout: device did not enter $mode within ${timeout}s"
}
