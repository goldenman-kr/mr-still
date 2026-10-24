# Mac App Store preparation

## Build variants

- `PhotoViewer` scheme: existing `Debug` / `Release` direct distribution builds; no App Sandbox or `APP_STORE` compilation condition.
- `PhotoViewer-AppStore` scheme: `AppStoreDebug` for development, `AppStore` for archive. Both enable App Sandbox and `APP_STORE`.
- App Store archive uses the same app identity and icon, macOS 14 minimum, and universal Apple Silicon / Intel architectures.
- `Resources/AppStore.entitlements` enables only sandbox, user-selected read/write files, app-scoped bookmarks, and printing. No blanket home-folder, Pictures, Downloads, network, automation, or temporary sandbox exceptions are granted.

## Local archive (no upload)

Run from the repository root:

```sh
scripts/archive-app-store.sh
```

The default creates an **unsigned local validation archive**, `build/AppStore/Mr.Still.xcarchive`. It is not eligible for upload. Use a new path for each run; existing archives are never overwritten.

For a signed archive, configure the matching Mac App Store distribution certificate and provisioning profile in Xcode first. Supply their identifiers externally; no credentials are stored in this repository:

```sh
APP_STORE_SIGNED_ARCHIVE=1 \
APP_STORE_TEAM_ID='YOUR_TEAM_ID' \
APP_STORE_SIGNING_IDENTITY='YOUR_DISTRIBUTION_IDENTITY' \
APP_STORE_PROFILE='YOUR_MAC_APP_STORE_PROFILE_NAME' \
scripts/archive-app-store.sh build/AppStore/Mr.Still-signed.xcarchive
```

The script does not export, upload, submit, or create account resources. Open the archive in Xcode Organizer, validate it, and select App Store Connect distribution when the account and listing are ready. Development or Developer ID signing is not a substitute for App Store distribution signing/profile. Publishing or updating an existing app also requires an eligible version/build number in `Resources/Info.plist`.

## Sandbox behavior

The first launch asks for a folder through the system open panel. Home is always shown below Favorites, followed by approved roots. Home is not traversed before approval; selecting it, expanding its disclosure arrow, or using the Home button requests a folder grant when needed. Approved Home expands one level only. Existing favorites remain visible but require approval when first used. Volumes are not implicitly traversed in this variant. Moving above an authorized root prompts for a parent grant; canceling preserves the current folder and history. Folder grants are stored as security-scoped bookmarks, restored without prompting at launch, and balanced on termination. Moved bookmark roots rebase persisted recent and favorite paths. Invalid/expired grants request approval again. Failure to save a bookmark is reported and may require approval after relaunch.

Finder file opens and the file picker request access to the containing folder if it has not already been approved, because the browser displays that folder's contents. Canceling leaves the current browser unchanged. Copy/paste retains temporary pasteboard access through completion; paste and trash require writable folder access. Native Finder reveal and system printing remain available. The Store variant's default-image-app menu explains Finder Get Info → Open with → Change All; the direct variant retains its existing batch-setting action.

## Privacy configuration

`PrivacyInfo.xcprivacy` is copied to the app bundle with these declarations:

- No tracking and no data collection by the app.
- UserDefaults: `CA92.1`, app-owned preferences, layout, recent items, favorites and bookmarks.
- File timestamps: `3B52.1` for metadata of files/folders selected by the user and `DDA9.1` for displaying creation/modification dates. Sorting, browsing and metadata display remain local.

English and Korean offline policies are bundled as `privacy-policy-en.html` and `privacy-policy-ko.html`. The Help menu opens the policy matching the app language. The publication source is [privacy-policy.md](privacy-policy.md).

App Store Connect still requires a **publicly accessible privacy policy URL**. Publish the reviewed policy and provide the resulting live URL in the listing; an offline copy or an unpublished repository file is not a completed store listing. The app currently supports the “Data Not Collected” response; reassess if adding network features, analytics, third-party SDKs or data handling changes.

## Items outside the code change

Before uploading or submission, the account owner must finish the Apple Developer membership and Mac App Store distribution profile/certificate, confirm the app identifier is available to that team, create the App Store Connect record, provide the public support/privacy URLs, descriptions and localized screenshots, complete age-rating/export-compliance/privacy answers, choose price/territories, accept the paid-app agreement and provide tax/banking details. No external account settings are changed by the archive script.

Sandbox behavior should be exercised using the App Store development build and a correctly signed archive/TestFlight build: fresh launch folder permission, reopening favorites/recent items, moved/unavailable folders, copying files across authorized folders, trash, Finder reveal, externally opened images, print, and permission cancellation/recovery. Automated builds or an unsigned archive alone do not prove store readiness or guarantee approval.

## Apple references

- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Security-scoped bookmark entitlements](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [Required-reason API categories and accepted reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Adding required-reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [App Store provisioning profiles](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Upload through Xcode Organizer](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html)
