#!/bin/zsh
# Create a local archive only. This does not export, upload, or submit the app.
set -eu
cd "${0:A:h:h}"
archive_path="${1:-build/AppStore/Mr.Still.xcarchive}"
if (( $# > 0 )); then shift; fi
if [[ -e "$archive_path" ]]; then
  print -u2 'Archive already exists. Choose a new output path.'
  exit 1
fi
python3 scripts/generate-project.py
# Default: unsigned validation archive. Supply signing options as build arguments
# for a signed archive, using credentials/profiles already configured in Xcode.
if [[ "${APP_STORE_SIGNED_ARCHIVE:-0}" == 1 ]]; then
  : "${APP_STORE_TEAM_ID:?Set APP_STORE_TEAM_ID to your developer team ID}"
  : "${APP_STORE_SIGNING_IDENTITY:?Set APP_STORE_SIGNING_IDENTITY to your distribution signing identity}"
  : "${APP_STORE_PROFILE:?Set APP_STORE_PROFILE to the matching Mac App Store profile name}"
  signing_options=("DEVELOPMENT_TEAM=$APP_STORE_TEAM_ID" "CODE_SIGN_IDENTITY=$APP_STORE_SIGNING_IDENTITY" "PROVISIONING_PROFILE_SPECIFIER=$APP_STORE_PROFILE")
else
  signing_options=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi
xcodebuild -project PhotoViewer.xcodeproj -scheme PhotoViewer-AppStore \
  -configuration AppStore -destination 'generic/platform=macOS' \
  -derivedDataPath build/AppStoreDerivedData -archivePath "$archive_path" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO "${signing_options[@]}" "$@" archive
print "Local archive: $archive_path"
if [[ "${APP_STORE_SIGNED_ARCHIVE:-0}" != 1 ]]; then
  print 'Unsigned validation archive: not uploadable. Distribution signing/profile and App Store validation are still required.'
fi
