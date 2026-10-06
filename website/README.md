# QuickTile public pages

These dependency-free pages use original vector geometry, system fonts, local assets, and no tracking. The support and privacy repositories are explicitly separate from the app source repository. Release-download buttons are omitted until real URLs are configured.

`config.json` owns the production destinations. Its `repositoryURL` is reserved for the **application source**, and is intentionally empty; `supportRepositoryURL` is the issue tracker. No fake download or source links are generated.

Build and validate both configured publication outputs without publishing:

```sh
python3 Scripts/build-website.py --site support --mode publish
python3 Scripts/verify-website.py --site .build/website/support --publish
python3 Scripts/build-website.py --site privacy --mode publish
python3 Scripts/verify-website.py --site .build/website/privacy --publish
```

The support site's root is a small directory with setup/privacy navigation and a real contact. The privacy site's root shows the policy. Navigation and canonical metadata cross-link the official support and privacy pages, while all local asset paths remain safe under a GitHub Pages project path.

Export verified publication outputs into the standalone documentation folders with
`python3 Scripts/export-website-folders.py`. Use `--dry-run` to inspect destinations.
The exporter does not initialize Git or publish; it refuses to overwrite unknown or
locally modified files. The standalone Pages workflow uploads only static pages and
assets, excluding repository documentation and export metadata.

For a local draft with incomplete destinations, use `--mode draft` and omit `--publish` from verification. Drafts disable search indexing and publication verification rejects them. The scripts never upload content or make network requests.

Visual review is separate from structural verification. Check desktop/mobile, light/dark appearance, keyboard focus, zoom, text wrapping, and the final hosted paths before publication. No app-store approval or vendor-action validation is implied by this site.
