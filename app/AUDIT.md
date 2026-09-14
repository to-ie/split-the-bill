# Audit

A pass over the whole app for bugs, interface and interaction problems,
security, and the one claim it has to keep: that receipt data stays on the
phone. Everything below was either fixed or is listed as a known limitation.

Verification commands are given where a finding can be re-checked, because a
claim about data leaving a device is worth being able to test rather than
trust.

---

## Data never leaves the phone

### Fixed: Android was backing the receipts up to Google Drive

**This was the most serious finding.** `android:allowBackup` defaults to
`true`, and nothing had set it. Android Auto Backup therefore treated the
app's data directory as eligible, which is every receipt, every friend's
name, and the PIN — uploaded to the user's Google Drive, encrypted in
transit but nonetheless off the device.

Fixed in three places, because one is not enough across versions:
`android:allowBackup="false"`, `android:fullBackupContent="false"`, and an
`@xml/data_extraction_rules` that refuses both cloud backup and
device-to-device transfer.

```bash
aapt2 dump xmltree app-release.apk --file AndroidManifest.xml | grep -i backup
```

The cost is deliberate: a new phone starts empty, and a lost phone means lost
bills. "There is no cloud copy to restore" is the design, not an oversight.

### Fixed: photographs of receipts were kept for ever

Both the camera and the gallery picker hand back a file in the app's cache.
Nothing deleted it. Every scan left a full-resolution photograph of somebody's
bill on the phone indefinitely — and **"Clear all data" did not touch them**,
so the app wiped the receipts while keeping pictures of them.

The working copy is now deleted as soon as the text has been read, on success
and on failure, and "Clear all data" sweeps the caches. The gallery file is a
copy the picker made, so removing it never touches the user's own photo.

### Fixed: the PIN was stored in plain text

`bill_store.json` contained the PIN as typed. It now holds a salted SHA-256,
with a fresh random salt per install, and PINs written by earlier builds are
converted on first load and the plaintext removed from disk.

Being honest about what this does: four digits is ten thousand possibilities,
so it does not stop anyone who has the file and wants to spend a second on it.
What it stops is *disclosure* — by a bug report, a file manager, a support
request — which matters because people reuse the PIN that unlocks their phone.

### Fixed: the task switcher showed the last screen

Android photographs the app as it leaves the foreground to draw the thumbnail,
and that photograph sat in the task switcher for whoever picked the phone up.
When a PIN is set, the app now covers itself the moment it stops being
frontmost, so the thumbnail is of the cover.

### Verified: no network permission, and no network code

The release manifest grants `CAMERA` and local photo access, and nothing else.
The `camera` and `image_picker` plugins each merge `INTERNET`,
`ACCESS_NETWORK_STATE` and `RECORD_AUDIO` into the manifest; all three are
removed with `tools:node="remove"`.

```bash
aapt2 dump permissions app-release.apk | grep uses-permission
```

There should be no `INTERNET` line. This is the enforcement: not the absence
of calls in the code, but the absence of the permission, which the operating
system applies whatever the code or its dependencies try to do.

Two supporting facts:

- **No network code.** Nothing under `lib/` imports an HTTP client, opens a
  socket, or constructs a remote URL.
- **A transitive HTTP library exists** in the dependency graph, pulled in by
  `image_picker_platform_interface`. It is never imported by this app, and it
  could not reach anything if it were.

`flutter run` builds a *debug* APK, and Flutter puts `INTERNET` into the debug
and profile manifests because hot reload needs a socket. Only the release
build carries the claim.

### Verified: the OCR model is on the device

The Latin recognition model and its native pipeline ship inside the APK
(`assets/mlkit-google-ocr-models/`, plus `libmlkit_google_ocr_pipeline.so`).
ML Kit's terms also mention model updates and telemetry; without the network
permission the SDK cannot do either.

The empirical test, per the brief: install the release APK, turn off wifi and
mobile data, and scan a receipt.

### Verified: nothing unexpected is stored

The store holds three keys — settings, friends, groups. No device identifier,
no install identifier, no timestamps, no telemetry. There is a test asserting
exactly that set, so adding a field is a deliberate act rather than a drift.

### Fixed: the release was signed with the shared Android debug key

Every Android SDK ships the same debug keystore, so a debug-signed release
could be replaced by an APK that anybody built, inheriting its data directory.
Release builds are now signed with a real 4096-bit key kept outside the
repository at `~/.split-the-bill/upload-keystore.jks`, with its passwords in a
gitignored `android/key.properties`. A build without the key still works and
warns rather than failing.

**This changes the signature, so the existing app has to be uninstalled before
the next one installs.** Back up nothing: there is nothing to back up to.

### Known limitation: the store is not encrypted

`bill_store.json` sits in the app's private directory, which other apps cannot
read on an unrooted device, but it is plain JSON. On a rooted phone, or via a
USB backup of a debuggable build, it is readable.

Encrypting it with a key from the Android Keystore is the fix, and it is a
real piece of work: key generation and rotation, migration of existing stores,
and a decision about what happens when the key is invalidated (which Android
does when the screen lock changes). Worth doing; not done.

### Known limitation: sharing goes through the clipboard

"Share the split" copies plain text. That is a deliberate design — no
messaging SDKs, no network — but the clipboard is readable by other apps while
it holds the text, and Android shows a preview of it. Marking the clip
sensitive requires platform code, which the brief's iOS-portability rule
discourages.

---

## Bugs found and fixed

**A finished one-off split disappeared.** Completing a one-off saved it into a
hidden group and then showed it nowhere — not on the home screen, not in the
archive. The receipt existed in storage and was unreachable. One-offs now
appear on home like any other group, while still not being offered as a
destination for a second receipt.

**A friend who paid a bill could be deleted.** Removal was blocked only when
someone had *items* assigned. Deleting the person who paid left the receipt
reading "Paid by ?" and the group crediting a friend who no longer existed.
Removal is now refused when someone paid a bill, is on a bill, or has settled
up, and the refusal says which bill.

**A corrupt store wiped everything silently.** Any parse failure fell through
to a fresh seed, and the first subsequent edit overwrote the unreadable file.
The file is now copied aside before anything else happens, and the app says so
instead of looking like a fresh install.

**Two saves could race.** Every mutation encoded the whole store and wrote it
without waiting for the previous write. Writes are queued now.

**"Edit" on a receipt opened the read-only view.** It goes to the editor.

**"Edit" beside a group's members started a new bill.** A group's members are
whoever has been on one of its receipts, so there is no separate list to edit.
The button is gone and a line says where members come from.

---

### Fixed: the group menu never opened

Tapping the three dots on a group did nothing. The menu was being built every
time and failing during layout before it could paint: a `Positioned` child in
a `Stack` is measured against unbounded constraints unless both horizontal
edges are given, and the menu's column stretched, so it asked for infinite
width and threw. Silent, because a layout exception in release simply renders
nothing.

### Fixed: two ways of clearing a debt that could not agree

See LOGIC-CHANGES.md. "Mark as settled" and "Mark paid" were separate
mechanisms; in the worst order the payer went from being owed twenty to owing
twenty. Keeping both and reconciling them turned out to leave a subtler fault
of its own, so there is one mechanism now: a debt is cleared by recording a
payment, and nothing else. `test/settlement_maths_test.dart` covers the
arithmetic exhaustively, including six hundred randomly generated groups
settled one payment at a time.

### Fixed: a receipt could not be deleted

The state layer supported it; the interface offered no way in. The receipt
menu is now Edit and Delete.

### Fixed: stale photos were never swept

The working copy is deleted as soon as its text has been read, but a crash
between the two left one behind. The caches are now swept at launch as well as
on "Clear all data".

## Interface

A stress test now walks the entire app — every screen, the whole six-step flow,
the editor — at 320, 390 and 430 pixels wide, at 1.0, 1.3 and 1.6 times text
size, in both themes, and fails on any overflow. It found three:

- the running-total rows on the correction screen, where a long label and a
  long amount met at large text;
- the shutter row, whose fixed 38-pixel gaps did not survive a 320-pixel
  screen;
- the screen header, where the "Split equally" pill grew at large text until
  it pushed the title off the bar.

All three are fixed, and the stress test stands to catch the next one.

---

## Interaction

Smaller things noticed and changed while reading the flows:

- The settle-up rows could not fit two names, an amount and a button on one
  line, so names wrapped and read as a bug. They show the amount, with names a
  tap away on the avatars, and the full sentence still goes to screen readers.
- The row editor sat under the keypad on a long receipt. It scrolls to the top
  of the remaining space, re-scrolls when the keyboard opens, the screen's own
  call to action hides while a row is open, and the keyboard's return key
  commits so Done need not be reached at all.
- A swiped line now names itself in the confirmation, rather than asking a
  blind "are you sure".

---

## Known limitations

- **The camera path has never run on real hardware.** It compiles, the model
  is in the APK, and the failure modes are now reported individually rather
  than as one message about lighting. It has only ever been exercised through
  the fake engine.
- **The store is not encrypted** (above).
- **No undo for a deleted receipt.** Lines can be recovered by not confirming;
  a whole receipt cannot.
- **A group currency override relabels, it does not convert.** Documented
  behaviour from the prototype. Conversion needs rates, and rates need the
  network.
