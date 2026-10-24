#!/bin/zsh
# Package an already-built app. Sign/notarize separately before publishing.
set -eu
cd "${0:A:h:h}"
app_path="${1:-build/Distribution/Build/Products/Release/Mr. Still.app}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
output_path="${2:-build/Releases/Mr.Still-${version}-universal.dmg}"
if [[ ! -d "$app_path" || -e "$output_path" ]]; then
  print -u2 'App must exist and output DMG must not already exist.'
  exit 1
fi
mkdir -p "${output_path:h}"
staging_path=$(mktemp -d "${TMPDIR:-/tmp}/mr-still-dmg.XXXXXX")
trap 'rm -rf "$staging_path"' EXIT
/usr/bin/ditto --norsrc "$app_path" "$staging_path/Mr. Still.app"
ln -s /Applications "$staging_path/Applications"
cat > "$staging_path/설치 안내.txt" <<'TEXT'
Mr. Still — macOS 14 이상

Mr. Still 앱을 Applications 폴더로 드래그한 뒤,
디스크 이미지를 추출하고 응용 프로그램 폴더에서 실행하세요.

다운로드 및 설치 관련 안내:
https://github.com/goldenman-kr/mr-still/releases/latest
TEXT
/usr/bin/hdiutil create -volname 'Mr. Still' -srcfolder "$staging_path" -fs HFS+ -format UDZO "$output_path"
