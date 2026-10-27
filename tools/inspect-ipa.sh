#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash tools/inspect-ipa.sh /path/to/app.ipa" >&2
  exit 2
fi

IPA="$1"
if [[ ! -f "$IPA" ]]; then
  echo "File not found: $IPA" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP" ]]; then
  echo "No Payload/*.app directory found in IPA." >&2
  exit 1
fi

PLIST="$APP/Info.plist"
plist_value() {
  local key="$1"
  if [[ -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null && return 0
  fi
  python3 - "$PLIST" "$key" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as stream:
    data = plistlib.load(stream)
value = data.get(sys.argv[2], "")
print(value if value is not None else "")
PY
}

EXECUTABLE="$(plist_value CFBundleExecutable)"
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
VERSION="$(plist_value CFBundleShortVersionString)"
printf 'App: %s\nBundle ID: %s\nVersion: %s\nExecutable: %s\n' \
  "$(basename "$APP")" "$BUNDLE_ID" "$VERSION" "$EXECUTABLE"

BIN="$APP/$EXECUTABLE"
if [[ -f "$BIN" ]]; then
  file "$BIN"
  if command -v llvm-objdump >/dev/null 2>&1; then
    llvm-objdump --macho --private-headers "$BIN" 2>/dev/null \
      | grep -E 'LC_ENCRYPTION_INFO|Mach header|cputype|filetype|cryptid' \
      | head -20 || true
  fi
  if command -v strings >/dev/null 2>&1; then
    echo
    echo 'Relevant embedded identifiers (read-only scan):'
    strings -a "$BIN" | grep -Ei \
      'ResolutionSelectorPanel|Vip1080RequiredPromptModifier|lockPlaybackResolution|vip1080ResolutionTitle|rewardAdTimePoints1080p|TradPlusAdService|VIPService|api\.pinatv' \
      | sort -u || true
  fi
fi
