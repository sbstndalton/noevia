#!/bin/sh
# `swift test` on a Mac with only the Command Line Tools (no Xcode). There, SwiftPM's default
# build backend fails to start ("Unknown error parsing property list") and the native backend
# does not find swift-testing on its own. With Xcode installed (as on CI), plain `swift test`
# works and this script is not needed.
set -eu
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
exec swift test --build-system native \
  -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
  -Xlinker -F -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
  "$@"
