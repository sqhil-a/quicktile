# QuickTile website

The website lives alongside the application in https://github.com/sqhil-a/quicktile. GitHub Pages publishes one site with support and privacy subpages:

- https://sqhil-a.github.io/quicktile/
- https://sqhil-a.github.io/quicktile/support.html
- https://sqhil-a.github.io/quicktile/privacy.html

`config.json` owns production links, contact details and the application issue tracker. Download buttons remain hidden until signed release URLs exist. Pages use system fonts, local CSS/vector assets and no tracking.

Build and validate without publishing:

```sh
python3 Scripts/build-website.py --site support --mode publish --output .build/public-site
python3 Scripts/verify-website.py --site .build/public-site --publish
```

The `.github/workflows/pages.yml` workflow performs these checks and deploys only generated static files. Application source, signing files and build metadata are never included in the website artifact. The older standalone exporter is optional tooling, not the production deployment route.

Visual review is separate from structural verification. Check mobile/desktop, light/dark appearance, focus, zoom and wrapping. Website publication does not imply App Store approval.
