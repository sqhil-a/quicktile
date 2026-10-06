# Deployment status

Recorded October 5, 2026. This is release evidence, not an App Store approval claim.

## Published websites

- Support: https://sqhil-a.github.io/quicktile/support.html
- Privacy: https://sqhil-a.github.io/quicktile/privacy.html
- Application source: https://github.com/sqhil-a/quicktile

The application source was published at commit `4d9a0ed3034346479179e59c84ead8019dfe435a`. A credential-pattern scan passed; build artifacts, API keys, signing material and provisioning profiles are excluded from Git. Both website repositories deploy through GitHub Actions. Initial deployments succeeded; all HTML, CSS, mark, robots and sitemap URLs returned HTTPS 200. Published HTML matched the verified local files. Prior local visual review covered 320, 390 and 1280 pixels, light/dark appearance. The subsequent remote browser preview was denied by browser access policy; it was not bypassed.

## iPhone distribution package

`.build/releases/AppStore-export/QuickTile.ipa` is version 1.0, build 5, bundle `sahil.QuickTile`, team `M26FDHM6XS`. Xcode exported it with **Cloud Managed Apple Distribution** and an App Store provisioning profile. Deep strict signature verification passed. IPA SHA-256: `403d10f2a25e9b3d056ed2bee7406d83c64600bd14e8c33695e8a14a7c8c5d60`. Distribution entitlements disable `get-task-allow` and include `beta-reports-active`. The archive includes privacy disclosures, real support/privacy URLs, required permission descriptions, and the reviewed OS-only encryption declaration. No test bundle is included.

Export succeeded with automatic provisioning. This does not establish App Store Connect validation or acceptance. The build used Xcode 27 beta build `27A5252f`; use an accepted release Xcode before submission. Do not upload an unsigned or development-signed artifact in place of the distribution IPA.

## Still required before public release

- Build/sign the universal Mac companion and helper with Developer ID, notarize/staple, verify Gatekeeper and clean install/upgrade, then publish its download.
- Complete App Store Connect record, final privacy answers, review contact, real screenshots, archive validation and TestFlight.
- Close physical-device, supported-runtime, accessibility, performance, actual app-mapping, media/hardware, voice execution and live agent/reply gates in `RELEASE_GATES.md`.
- Resolve the optional Mac private brightness adapter's distribution policy and support matrix.

App Store upload and release have not been performed. No unsigned Mac download is advertised as a release.
