#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/app.ipa" >&2
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
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || true)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"

printf 'App: %s\nBundle ID: %s\nVersion: %s\nExecutable: %s\n' \
  "$(basename "$APP")" "$BUNDLE_ID" "$VERSION" "$EXECUTABLE"

BIN="$APP/$EXECUTABLE"
if [[ -f "$BIN" ]]; then
  file "$BIN"
  if command -v llvm-objdump >/dev/null 2>&1; then
    llvm-objdump --macho --private-headers "$BIN" 2>/dev/null \
      | grep -E 'cryptid|LC_ENCRYPTION_INFO|LC_ENCRYPTION_INFO_64|Mach header|cputype|filetype' \
      | head -20 || true
  fi
  if command -v strings >/dev/null 2>&1; then
    echo
    echo 'Relevant embedded identifiers (read-only scan):'
    strings -a "$BIN" | grep -Ei \
      'ResolutionSelectorPanel|Vip1080RequiredPromptModifier|lockPlaybackResolution|vip1080ResolutionTitle|rewardAdTimePoints1080p|TradPlusAdService|VIPService|api\\.pinatv' \
      | sort -u || true
  fi
fi
