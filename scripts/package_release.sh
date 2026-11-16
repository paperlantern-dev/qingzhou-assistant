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
# Only the reviewed sample knowledge goes into the download (see stage_samples.sh): the owner's own
# knowledge base lives outside this folder and is never packaged.
bash scripts/stage_samples.sh knowledge-samples scripts/reviewed-samples.txt "$OUT/轻舟助手.app/Contents/Resources/示例知识库"
codesign --force --sign - "$OUT/轻舟助手.app" "$OUT/模拟微信.app"

ZIP="dist/qingzhou-assistant-$VERSION.zip"
ditto -c -k --norsrc --keepParent "$OUT" "$ZIP"
bash scripts/scan_release.sh "$ZIP"
echo "Built $ZIP"
