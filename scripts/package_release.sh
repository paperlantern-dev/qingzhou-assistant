#!/bin/bash
# Builds the download: dist/qingzhou-assistant-<version>.zip with 轻舟助手.app and 模拟微信.app.
# Universal (Apple silicon + Intel), ad-hoc signed (no personal certificate in it), and with
# the build machine's folder names kept out of the binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
FLAGS=(-c release --arch arm64 --arch x86_64 -Xswiftc -file-prefix-map -Xswiftc "$PWD=.")
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"
OUT="dist/轻舟助手 $VERSION"
rm -rf dist && mkdir -p "$OUT"

package() { # <app name> <executable> <plist> [icon.icns]
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$BIN/$2" "$app/Contents/MacOS/"
  strip -x "$app/Contents/MacOS/$2"
  cp "$3" "$app/Contents/Info.plist"
  if [ -n "${4:-}" ]; then cp "$4" "$app/Contents/Resources/"; fi
}
package "轻舟助手" QingzhouApp Resources/Info.plist Resources/AppIcon.icns
package "模拟微信" MockWeChat Resources/MockWeChat-Info.plist
# Only the sample files (示例-*) go into the download, never the rest of knowledge/, which may
# hold a real shop's prices. The build stops if a sample has a phone number, an email or a key in it.
SAMPLES="$OUT/轻舟助手.app/Contents/Resources/示例知识库"
mkdir -p "$SAMPLES"
cp knowledge/示例-* "$SAMPLES/"
SKIPPED="$(find knowledge -type f ! -name '示例-*' ! -name '.*' | wc -l | tr -d ' ')"
if [ "$SKIPPED" != "0" ]; then echo "Not packaged: $SKIPPED file(s) in knowledge/ that are not named 示例-*"; fi
if grep -rnE '1[3-9][0-9]([ -]?[0-9]){8}|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}|sk-[A-Za-z0-9_-]{16,}' "$SAMPLES"; then
  echo "Stopped: the sample knowledge above looks private (phone number, email or API key)." >&2
  exit 1
fi
codesign --force --sign - "$OUT/轻舟助手.app" "$OUT/模拟微信.app"

ZIP="dist/qingzhou-assistant-$VERSION.zip"
ditto -c -k --norsrc --keepParent "$OUT" "$ZIP"
echo "Built $ZIP"
