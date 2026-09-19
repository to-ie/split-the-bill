# split-the-bill

Privacy-first bill splitting for Android. The app lives in [app/](app/).

**Landing page:** https://split.t-o.ie/

## Publishing the landing page

[.github/workflows/pages.yml](.github/workflows/pages.yml) publishes it on every
push to `main` that touches `dist/index.html`, `dist/robots.txt` or
`dist/site/`. It copies those three things into the artifact rather than
publishing `dist/` wholesale, so the Flutter web build in `dist/web/` and any
APKs sitting in `dist/` cannot end up on the site. The job fails if either
appears.

Once, in the repository settings: **Settings, Pages, Source: GitHub Actions**,
and **Custom domain: split.t-o.ie**. The workflow also writes a `CNAME` file
into the artifact, because a domain set only in the settings does not reliably
survive an Actions deployment, and losing it drops the site back to the
github.io address without saying so.

`split.t-o.ie` is a CNAME to `to-ie.github.io` in the t-o.ie zone.

## Releasing a build

The APKs are release assets, not files in the repository. Two of them come to
about sixty megabytes, and committing that on every build would sit in the
history for good. The download buttons point at
`releases/latest/download/bill-arm64.apk`, which always resolves to the newest
release, so the page needs no edit when a new one goes out.

```bash
cd app && flutter build apk --release --split-per-abi
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ../dist/bill-arm64.apk
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ../dist/bill-arm32.apk

gh release create v1.0.2 \
  ../dist/bill-arm64.apk ../dist/bill-arm32.apk \
  --title "1.0.2" --notes "Offline bill splitting for Android."
```

Until the first release exists, the download buttons will 404.

## Try it on your phone

```bash
./serve.sh
```

Open the address it prints on a phone on the same wifi, then tap **Install the app**.
Or open it in the phone's browser from the same page, with no install.

## Try it on this computer

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd app
flutter run -d chrome
```

## More

- [AUDIT.md](AUDIT.md) — security, privacy and bug audit, with what was fixed
- [app/README.md](app/README.md) — running, testing, rebuilding, project layout
- [LOGIC-CHANGES.md](LOGIC-CHANGES.md) — every correction made to the two specs, and why
- [receipt-splitter-brief.md](receipt-splitter-brief.md) — the original architecture brief
- [app/test/goldens/](app/test/goldens/) — every screen rendered at phone size, both themes
