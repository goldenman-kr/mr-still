#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration="${1:-Debug}"
if (( $# > 0 )); then shift; fi
python3 scripts/generate-project.py
xcodebuild -project PhotoViewer.xcodeproj -scheme PhotoViewer -configuration "$configuration" -derivedDataPath build/DerivedData "$@" build
