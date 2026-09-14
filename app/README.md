# BILL

Split a receipt without it ever leaving your phone. Photograph a bill, read it with
on-device OCR, correct what was misread, assign items to people, settle up.

No backend, no accounts, no cloud OCR, and no `INTERNET` permission in the release
Android manifest. That last one turns the privacy claim into something the operating
system enforces rather than something this README promises.

One caveat worth knowing: Flutter puts `INTERNET` into the *debug* and *profile*
manifests, because hot reload talks to your machine over a socket. Only
`flutter build apk --release` produces the build with camera permission and nothing
else, so that is the one to test the claim against.

Built from `receipt-splitter-brief.md` (architecture) and
`Bill split Android prototype/design_handoff_bill_split/` (screens and behaviour).
Where the two disagreed, see [LOGIC-CHANGES.md](LOGIC-CHANGES.md).

## Getting it onto a phone

From the repository root:

```bash
./serve.sh
```

It prints an address on your local network. Open that on a phone connected to the same
wifi and tap **Install the app**. Android will warn about an unknown source, which is
what sideloading looks like; allow it for your browser.

The same page offers the browser version if you would rather not install anything.

## Running it on this machine

The SDK lives in `~/development/flutter`. Put it on your `PATH` for the session:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

or append that line to `~/.bashrc` to make it permanent.

```bash
cd app
flutter run -d chrome
```

There is no camera in a browser, so the scan step loads a sample receipt through the
real parser and says so on screen. Everything else is the real app. Press `r` to hot
reload, `q` to quit. `Ctrl+Shift+M` in Chrome gives a phone-shaped viewport; the design
targets about 360px wide.

## Rebuilding the APK

The version lives in **three** places and none of them reads the others:
`pubspec.yaml` (`version:`), `lib/version.dart` (shown at the foot of Settings)
and `dist/index.html` (shown under the download buttons, twice). Change all
three, or the phone and the website will disagree about what you shipped.

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
cd app
flutter build apk --release --split-per-abi
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ../dist/bill-arm64.apk
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ../dist/bill-arm32.apk
```

### Checking the privacy claim

The release manifest grants camera and local photo access, and nothing else. Plugins
try to merge `INTERNET`, `ACCESS_NETWORK_STATE` and `RECORD_AUDIO` in; the app manifest
removes all three with `tools:node="remove"`. Re-check after any dependency change:

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

There should be no `INTERNET` line. The OCR model ships inside the APK
(`assets/mlkit-google-ocr-models/`), so recognition works with the network off, which
is the empirical test the brief asks for rather than a policy promise.

Note that `flutter run` builds a *debug* APK, and Flutter puts `INTERNET` into the
debug and profile manifests because hot reload needs a socket. Only the release build
carries the claim.

## Tests

```bash
cd app
flutter test                    # 59 tests
./tool/check_ocr_boundary.sh    # fails if ML Kit leaks out of its one file
```

The app itself starts empty: one user, no friends, no groups. The demo content used by
the tests and the screenshots lives in `test/fixtures.dart`, not in the app.

`test/screenshot_test.dart` renders every screen to `test/goldens/*.png` at phone size,
in both themes. Look at those PNGs to see the whole app without running it. Regenerate
after a UI change:

```bash
flutter test --update-goldens test/screenshot_test.dart
```

## Layout

```
app/lib/
  ocr/          the OCR boundary. mlkit_ocr_engine.dart is the ONLY file that
                imports ML Kit; everything else speaks plain Dart value types
  parsing/      words + geometry -> rows -> line items. No Flutter imports
  model/        data model and money. Division happens in integer cents
  logic/        shares, group aggregation, settle-up, share text
  state/        one ChangeNotifier plus JSON-on-disk storage
  theme/        design tokens, light and dark
  ui/           twelve screens and the widgets they share
```

Everything under `parsing/`, `model/` and `logic/` is pure Dart with no platform
imports, so it runs under `flutter test` in milliseconds and ports to iOS at zero cost.
That is most of the app's actual logic.

## What is not done

- The camera path has not been run on a real phone. It compiles and the model is in the
  APK, but the capture-to-OCR round trip has only been exercised through the fake
  engine. That is the first thing to try on the device.
- The PIN in Settings is stored but does not yet gate the app on open.
- A group currency override relabels amounts, it does not convert them. This matches
  the prototype; if conversion is wanted it needs rates, and rates need the network.
- No merge/split of OCR rows, and no bounding-box overlay on the photo (brief
  section 11). The geometry is retained, so both remain straightforward.
