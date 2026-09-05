#!/usr/bin/env bash
set -euo pipefail
TARGET="$1"
PRESET="$2"
BINARY="$3"
ROOT="$PWD"
mkdir -p "build/payloads/$TARGET"
godot --headless --path . --export-release "$PRESET" "build/payloads/$TARGET/$BINARY"
test -s "build/payloads/$TARGET/$BINARY"
cp LICENSE THIRD_PARTY_NOTICES.txt README.md build/payloads/$TARGET/
mkdir -p build/payloads/$TARGET/source
git archive HEAD | tar -x -C build/payloads/$TARGET/source
printf 'Source commit: %s\nGodot: %s-stable\n' "$GITHUB_SHA" "$GODOT_VERSION" > build/payloads/$TARGET/BUILD.txt
mkdir -p dist
if [[ "$TARGET" == windows-* ]]; then
  (cd build/payloads/$TARGET && 7zz a -t7z -m0=lzma2 -mx=9 -md=64m -ms=on "$ROOT/dist/FrameSyncLab-${TARGET}.7z" .)
  7zz t "dist/FrameSyncLab-${TARGET}.7z"
else
  if [[ "$TARGET" == macos-* ]]; then
    unzip -q build/payloads/$TARGET/FrameSyncLab.zip -d build/macos-unpacked/$TARGET
    cp -a build/macos-unpacked/$TARGET/*.app build/payloads/$TARGET/
    # Remove only the known intermediate archive from the payload.
    rm build/payloads/$TARGET/FrameSyncLab.zip
  else
    chmod +x build/payloads/$TARGET/FrameSyncLab.*
  fi
  XZ_OPT='-9e -T2' tar -cJf "dist/FrameSyncLab-${TARGET}.tar.xz" -C build/payloads/$TARGET .
  xz --test "dist/FrameSyncLab-${TARGET}.tar.xz"
fi
du -h dist/* >> "$GITHUB_STEP_SUMMARY"
