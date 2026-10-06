# Signing and distribution

The source, schemes, bundled agent-helper build step, iPhone privacy manifest, and archive/notarization scripts provide release preparation. The physical, vendor, privacy, and signature evidence in [RELEASE_GATES.md](RELEASE_GATES.md) is still required. Support/privacy websites are published and an iPhone App Store distribution IPA has been exported. No application release, store submission, or notarization is claimed. See [DEPLOYMENT_STATUS.md](DEPLOYMENT_STATUS.md). Listing copy, reviewer setup, and a local-export template are prepared in [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md).

## iPhone

Select your team on the QuickTile target, choose a unique bundle ID if required, and build to a physical iPhone. The original team and `sahil.QuickTile` identifier are preserved from the starter. Simulator unsigned builds verify code compilation but cannot be used to validate Keychain entitlements or physical permissions. Use normal Xcode signing to run security-dependent integration checks.

For distribution, run `bash Scripts/archive-release.sh iphone TEAM_ID BUILD_NUMBER`, then validate/export the archive in Xcode Organizer using the appropriate profile. Configure the version/build, App Store Connect metadata, accurate privacy labels, and screenshots. The confirmed [support](https://sqhil-a.github.io/quicktile/support.html) and [privacy](https://sqhil-a.github.io/quicktile/privacy.html) URLs and support email are configured in the app, with an offline privacy policy in Settings; publication and public reachability verified October 5, 2026. The application source repository is https://github.com/sqhil-a/quicktile. A signed companion-download URL remains pending. The clearly labeled Preview board supports layout and local-timer inspection without a Mac; review instructions must also explain the signed companion and real pairing. No App Store acceptance is claimed. Deployment minimum: iOS 18; iPhone portrait and both landscape orientations.

The archive/notarization scripts select a full Xcode locally without changing `xcode-select`: they respect `DEVELOPER_DIR`, use a selected full Xcode, or fall back to `/Applications/Xcode.app`. Set `DEVELOPER_DIR` explicitly to choose an accepted release Xcode. The current iPhone Info.plist declares `ITSAppUsesNonExemptEncryption=false` because the reviewed encryption is provided entirely by Apple OS APIs; Apple's table requires no App Store Connect encryption documentation for that case. Confirm the final archive and re-evaluate if the cryptographic code, dependencies, or features change. The rationale and submission metadata are in [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md).

## Mac

Choose a stable bundle ID (`sahil.QuickTile.Mac` by default). The companion is a menu-bar agent (`LSUIElement`). For local use, Xcode's Sign to Run Locally can create an ad hoc signature. An Apple-issued identity gives more reliable privacy permission tracking across rebuilds. Move the app to `/Applications` before registering launch at login.

For a release:

1. Run `bash Scripts/archive-release.sh mac TEAM_ID BUILD_NUMBER` to archive the **QuickTileMac** scheme for arm64 and x86_64 with Developer ID Application signing and hardened runtime. A valid certificate is required; the script does not supply one. Inspect the final app and its nested `Contents/Helpers/QuickTileAgentEvent` signature.
2. Keep App Sandbox disabled for the documented cross-app functionality. Retain only `com.apple.security.automation.apple-events`; do not add broad exception entitlements.
3. Check archive signatures/entitlements and run `bash Scripts/notarize-companion.sh APP_PATH KEYCHAIN_PROFILE OUTPUT_DIRECTORY`. The script verifies Developer ID signing, submits with `notarytool`, staples/validates the ticket, assesses Gatekeeper, and creates a ZIP/checksum. The named credentials must already exist in Keychain outside the repository. Script availability is not proof of a successful notarization.
4. Verify a clean install on a separate Mac. Exercise Local Network, Accessibility, Automation, login registration, pairing/pause/revocation, opt-in agent helper/hook trust, and upgrades with the final stable signature.
5. Review privacy manifests and any current distribution requirements against the actual SDK before submission. No manifest should claim data/API behavior that was not audited.

These are preparation steps, not claims of completed signing/notarization. No signing private key, certificate export, Apple account token, provisioning profile, or notarization credential belongs in source control.

The current brightness implementation dynamically loads private DisplayServices APIs. Decide and document its distribution-policy/implementation path before releasing; supported monitor testing alone does not resolve this gate. Review final privacy reports, bundled/custom artwork rights, and accepted SDK/submission requirements at submission time.

## Updates and uninstall

Companion settings include **Verify signed update…** for a locally selected newer `.app`. It checks bundle identity/version, a Developer ID signature from the installed release's team, and Gatekeeper, then shows manual replacement guidance. It does not download, execute, or replace the app. Ad hoc builds cannot establish the release team for this check. Publish and test a real project-owned signed companion download before release; no hosted update feed or download URL is currently claimed.

Quit before replacing the signed companion and retain the previous signed version for recovery. Verify preservation of Keychain credentials, layouts/icons/timers, privacy permissions, launch registration, and agent hooks on a clean machine. Trusted hooks are repaired only through an explicit user action, never silently on launch or upgrade.

To uninstall, disable launch at login and agent tracking, quit, then remove the Mac app. Tracking disable removes only QuickTile handlers; never delete a user's `.codex` or `.claude` directory. Optional Mac data is under `~/Library/Application Support/QuickTile`; QuickTile Keychain credentials remain until explicitly forgotten/revoked. On iPhone, forget the Mac to remove its pairing credential and remove the app to remove its container data.

## Reproducibility

No external Swift dependencies, generated network secrets, or third-party app artwork are needed to build. Both schemes live in `QuickTile.xcodeproj/xcshareddata/xcschemes`. Python scripts reconstruct project targets and test targets; the original icon artwork has a deterministic Swift generator. The generated PNGs are included so ordinary Xcode builds do not run an asset generation step.
