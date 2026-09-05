#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
PRESET="$2"
BINARY="$3"
ROOT="$PWD"
if [[ "$TARGET" == windows-* ]]; then
  SEVEN_ZIP="${SEVEN_ZIP:-$(command -v 7zz || command -v 7z || true)}"
  if [[ -z "$SEVEN_ZIP" ]] || ! command -v "$SEVEN_ZIP" >/dev/null 2>&1; then
    echo "7-Zip not found; install 7zip (7z or 7zz) before exporting." >&2
    exit 1
  fi
fi
mkdir -p "build/payloads/$TARGET"
godot --headless --path . --export-release "$PRESET" "build/payloads/$TARGET/$BINARY"
test -s "build/payloads/$TARGET/$BINARY"
printf 'Source commit: %s\nSource URL: https://github.com/%s/tree/%s\nGodot: %s-stable\n' "$GITHUB_SHA" "$GITHUB_REPOSITORY" "$GITHUB_SHA" "$GODOT_VERSION" > "build/payloads/$TARGET/BUILD.txt"
items=("$BINARY" "BUILD.txt")
mkdir -p dist
if [[ "$TARGET" == windows-* ]]; then
  (cd build/payloads/$TARGET && "$SEVEN_ZIP" a -t7z -m0=lzma2 -mx=9 -md=64m -ms=on "$ROOT/dist/FrameSyncLab-${TARGET}.7z" "${items[@]}")
  "$SEVEN_ZIP" t "dist/FrameSyncLab-${TARGET}.7z"
else
  if [[ "$TARGET" == macos-* ]]; then
    unzip -q build/payloads/$TARGET/FrameSyncLab.zip -d build/macos-unpacked/$TARGET
    apps=(build/macos-unpacked/"$TARGET"/*.app)
    [[ ${#apps[@]} -eq 1 && -d "${apps[0]}" ]]
    cp -a "${apps[0]}" "build/payloads/$TARGET/"
    items=("$(basename "${apps[0]}")" "BUILD.txt")
    # Remove only the known intermediate archive from the payload.
    rm build/payloads/$TARGET/FrameSyncLab.zip
  else
    chmod +x build/payloads/$TARGET/FrameSyncLab.*
  fi
  XZ_OPT='-9e -T2' tar -cJf "dist/FrameSyncLab-${TARGET}.tar.xz" -C "build/payloads/$TARGET" "${items[@]}"
  xz --test "dist/FrameSyncLab-${TARGET}.tar.xz"
fi
du -h dist/* >> "$GITHUB_STEP_SUMMARY"
