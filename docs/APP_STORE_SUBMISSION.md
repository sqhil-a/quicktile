# App Store submission preparation

This package prepares the iPhone listing and reviewer workflow. It does not represent a submitted build or a public release. Keep [RELEASE_GATES.md](RELEASE_GATES.md) open until the corresponding physical, vendor, privacy, and signing evidence exists. The macOS companion uses separate Developer ID distribution; it is not a Mac App Store build.

## Listing draft

| Field | Prepared value |
|---|---|
| Name | QuickTile; availability must be confirmed in App Store Connect |
| Subtitle | Mac controls on your iPhone |
| Primary category | Productivity; publisher confirms final category |
| Price | Free; no purchases or subscription in current source |
| Version | 1.0 in the current project; use the final archive's version |
| Bundle identifier | `sahil.QuickTile`; confirm the registered identifier and selected signing team |
| Copyright | 2026 Sahil Ambegaonkar; confirm the legal rights holder before submission |
| Support URL | [Prepared support page](https://sqhil-a.github.io/quicktile/support.html); published; HTTPS reachability verified October 5, 2026 |
| Privacy Policy URL | [Prepared privacy policy](https://sqhil-a.github.io/quicktile/privacy.html); published; HTTPS reachability verified October 5, 2026 |
| Support contact | [sahilambegaonkar@gmail.com](mailto:sahilambegaonkar@gmail.com) |
| Marketing URL | Optional published project home page; not yet assigned |
| App source | Public application-source repository URL not yet supplied |
| Companion download | Stable HTTPS URL for the signed/notarized Mac companion; not yet assigned |
| Review contact | Confirmed email: `sahilambegaonkar@gmail.com`; publisher supplies legal name and phone in international format privately in App Store Connect |
| Release | Select manual release when preparing the first submission; no upload or release is authorized by this document |

The application, support site and privacy policy are maintained together in https://github.com/sqhil-a/quicktile. The iPhone Settings screen links to the unified GitHub Pages subpages and includes an offline policy. A signed companion download remains pending.

Promotional text:

```text
Create personal Mac control boards on your iPhone. Open apps, run shortcuts, and keep timers close, with no QuickTile account or subscription.
```

Keywords:

```text
control,boards,remote,shortcuts,productivity,keyboard,launcher,timer,workflow
```

Description:

```text
QuickTile puts your Mac controls on your iPhone.

Build boards for the apps and workflows you use. Open Mac apps and websites, send keyboard shortcuts, control playback, adjust supported output volume, and run your existing Apple Shortcuts. Add a timer, combine actions into a sequence, or use an Assistant tile for supported voice commands.

Eight tile slots fit on each page in portrait or landscape. Hold a tile to edit and move it, add pages and boards, choose your own icons, and share editable board files. Preset boards are starting points you can customize for your app version and keyboard setup.

QuickTile pairs with the free Mac companion over your local network. You approve the iPhone on your Mac, and the connection is authenticated and encrypted. There is no QuickTile account, advertising, purchase, or subscription. Optional voice commands use your own Groq API key and may incur Groq usage charges. Audio stays on your iPhone; transcripts and available Mac app and Shortcut names go to Groq after your consent.

Timers work on your iPhone, including while the Mac is disconnected. Optional notifications can announce completion. The labeled Preview board lets you explore the layout and local timers before pairing.

Mac controls require the QuickTile companion on an awake Mac and both devices on the same reachable local network. Some actions need Mac Accessibility or Automation permission. Third-party keyboard actions depend on the focused panel and your app's keymap; posted keys do not guarantee an app performed the shortcut. Hardware output support varies.

Requires iOS 18 or later and a Mac with macOS 14 or later. Download and setup instructions for the companion are available from the support page.
```

The prepared text is within Apple's current field limits. Final screenshots must show the submitted app in use; use a useful real board, page editing, action configuration, and pairing. Label any Preview screenshot clearly. Avoid third-party artwork without rights and claims of verified vendor shortcuts, universal output support, or App Store approval. Do not enter an invented age rating: complete the current questionnaire against the final app, including website-opening behavior. [Apple metadata requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Reviewer notes draft

Replace the remaining URL/version fields with the verified release values before pasting these notes:

```text
QuickTile organizes Mac controls into boards on your iPhone. Mac execution requires the free signed companion at the companion download URL supplied with this submission. There is no QuickTile account or sign-in. Optional voice commands use the reviewer’s own Groq key, require explicit consent and on-device Microphone/Speech Recognition permissions; this feature can be left unconfigured. Pairing requires local access to both devices; no preconfigured or permanent pairing secret is supplied.

1. Install the supplied signed companion on a Mac with macOS 14 or later, move it to Applications, and open QuickTile Mac.
2. Connect the Mac and iPhone to the same reachable local network. Ethernet on the Mac works. Allow Local Network access when requested.
3. Choose Pair an iPhone in the companion. In QuickTile on iPhone, choose Pair with your Mac and scan the QR. The Mac displays a request: verify the phone name and choose Connect. The invitation expires after two minutes. Pair without a camera is also available using the full temporary invitation.
4. Choose a blank or editable preset board. Add a Mac app tile and tap it to open that app. Hold a tile or choose Edit page to inspect page editing. Add a timer to test the local timer behavior.
5. Keyboard and default Mac playback controls require Accessibility for QuickTileMac. A selected Music/Spotify player uses Automation instead. Permissions are requested only for the relevant features; simple app launch and local timers need neither. Test keyboard mappings in a disposable document with the expected panel focused.
6. Pause Connections on the Mac to see the paused phone state; resume and reconnect. Revoke the phone in the companion to end its authorization.

Without a Mac, choose Preview board on the initial iPhone screen. The screen is clearly labeled Preview. Its timers run locally; its other tiles only display a preview message and never claim to execute Mac actions. Preview is supplementary; the supplied real-device demonstration covers companion-dependent execution.

Opt-in local coding-agent tracking is configured in companion Settings. It installs only QuickTile-owned local lifecycle hooks; Codex hook trust requires a separate user action. This setup is optional for ordinary board use.
```

Attach a short recording of the final signed build pairing and executing an app/key/Shortcut action on real devices. Explain the companion dependence in the listing and review notes; do not assume Preview demonstrates full functionality or grants an exception to Apple's completeness/dependency rules. [App Review Guidelines 2.1, 4.2.3, and 5.1.1](https://developer.apple.com/app-store/review/guidelines/).

## Archive and export

The archive and notarization scripts respect an explicit `DEVELOPER_DIR`, use the selected full Xcode when available, and fall back to `/Applications/Xcode.app` when the global selection is only Command Line Tools. They fail if no full Xcode is available and never change the global selection. Set the intended release Xcode explicitly for this shell when needed:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
xcodebuild -version
bash Scripts/archive-release.sh iphone TEAM_ID BUILD_NUMBER
```

Confirm that Xcode/SDK is accepted at submission time. The recorded `27A5252f` installation is a beta build and is not submission evidence. Use an increasing final build number and preserve the registered bundle ID. Validate the archive in Organizer and inspect its privacy report and signed entitlements.

For a **local** IPA export, copy [AppStoreExportOptions.plist.template](../Configuration/AppStoreExportOptions.plist.template) to a private working path, replace `TEAM_ID`, and run:

```sh
xcodebuild -exportArchive \
  -archivePath .build/releases/QuickTile.xcarchive \
  -exportOptionsPlist /absolute/path/AppStoreExportOptions.plist \
  -exportPath .build/releases/iphone-export
```

The template's destination is `export`; it does not request an upload. A certificate/profile and valid team entitlement are still required. TestFlight upload, external testing, App Review submission, and publishing are separate publisher actions. [Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/).

## Privacy and export compliance

The final local unsigned iPhone Release archive contains `PrivacyInfo.xcprivacy`: tracking false, optional assistant Other User Content and Other Usage Data entries linked to the provider account for app functionality, UserDefaults reason `CA92.1`, and file-timestamp reasons `C617.1`/`3B52.1`. Its Info.plist includes the configured privacy/support URLs, support email, and false nonexempt-encryption declaration. That verifies resource and metadata inclusion in this archive, not signing or the publisher's final privacy answers. The current **Review optional voice User Content and Other Usage Data declarations** label remains a draft: assess direct favicon traffic, local paired-device metadata, optional player/agent behavior, and any future services against the final build. [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

The offline policy and support/policy links are implemented in iPhone Settings. Publish the confirmed policy and support pages, verify both URLs without sign-in, and review the final content against retention/deletion and opt-out behavior. A placeholder page or a future companion-download link cannot satisfy the final submission. [Apple privacy-policy requirement](https://developer.apple.com/app-store/review/guidelines/).

The current source uses TLS-PSK through Apple's Network/Security implementation, Keychain, SHA-256 through Apple CryptoKit, and URLSession HTTPS. It contains no custom or bundled third-party encryption implementation. The iPhone Info.plist declares `ITSAppUsesNonExemptEncryption=false`: the app uses encryption, but its current encryption is limited to the Apple operating system. Apple's documentation table says this case requires no encryption documentation in App Store Connect. The publisher must confirm the declaration in the final archive and re-evaluate it if cryptographic code, dependencies, or features change; this is not a claim that QuickTile uses no encryption. [Apple encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/), [encryption declaration key](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

Before final submission, close the applicable release gates, confirm current age-rating/territory/accessibility declarations and legal contact details, test signed permissions and oldest/current runtime behavior, validate the final archive, and supply a working signed companion download. Private DisplayServices in the separate Mac companion remains an explicit distribution-policy decision; it must not be represented as a public API or a notarized release.
