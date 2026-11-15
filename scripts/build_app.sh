#!/bin/bash
# Builds 轻舟助手.app and 模拟微信.app into ./build, signed with a stable identity
# (so the Screen Recording / Accessibility permissions survive rebuilds).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk 'NR==1{print $2}')}"

package() { # <app name> <executable> <plist> [icon.icns]
  local app="build/$1.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$BIN/$2" "$app/Contents/MacOS/"
  cp "$3" "$app/Contents/Info.plist"
  if [ -n "${4:-}" ]; then cp "$4" "$app/Contents/Resources/"; fi
  codesign --force --sign "${IDENTITY:--}" "$app"
  echo "Built $app"
}
package "轻舟助手" QingzhouApp Resources/Info.plist Resources/AppIcon.icns
package "模拟微信" MockWeChat Resources/MockWeChat-Info.plist
