# split-the-bill

Privacy-first bill splitting for Android. The app lives in [app/](app/).

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
