# Handoff: BILL — bill-splitting Android app

## Overview
BILL is a privacy-first Android app that photographs a restaurant/shop receipt, extracts line items with on-device OCR, lets the user correct the transcription, assign items to friends, and share who owes what. Bills can live inside long-running **groups** (e.g. a trip) that aggregate many receipts, track who paid each one, and compute a minimal set of settle-up payments.

This handoff accompanies the technical brief (`receipt-splitter-brief.md`, provided separately by the owner) which fixes the stack: **Flutter/Dart, Android-first, ML Kit on-device OCR, sqflite/JSON local storage, no backend of any kind.** Receipt data never leaves the device.

## About the design files
The files in this bundle are **design references created in HTML** — an interactive prototype showing intended look and behaviour, not production code. The task is to **recreate these screens in Flutter** following the brief's architecture (OCR boundary, pure-Dart parsing). `Bill Split App.dc.html` is the prototype (open in a browser; `android-frame.jsx` is only the device bezel used for presentation; `logo.png` is the app logo). All business logic worth keeping is specified in **LOGIC.md** — you should not need to reverse-engineer the HTML.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, copy and interaction patterns are final intent. Recreate them with Flutter widgets (Material 3 as the base, restyled with the tokens below).

## Design tokens

Light theme:
- Background `#F7F4EE` · Card `#FFFFFF` · Card border `#E5E0D2` (1.5px) · Dashed rules `#D8D2C2`
- Ink (text) `#1E2749` · Muted text `#8B8677` · Subtle chip bg `#EDE9DE`
- Brand green `#10A374` (primary buttons, selected states; button base shadow `0 2px 0 #0B845E`)
- Green tint `#E4F4EC` on `#0B845E` (positive chips/banners)
- Amber warning `#FCF8EC` bg, `#EFE4C3` border, `#C89B2A` icon
- Error red `#C44536` (tint bg `#FBEAE5`, text `#A93A26`)
- Gold accent `#E2A21B` (from logo coin)

Dark theme (Settings toggle, applies app-wide incl. status bar):
- Background `#14181F` · Card `#1E242E` · Border `#2B3240` · Dashed `#39414F`
- Ink `#EFECE2` · Muted `#98948A` · Chip `#2A303C`
- Green tint `#143528` on `#4CCB9A` · Amber `#2C2716`/`#4A4128` · Error tint `#3A1D16` on `#E8836C`
- "Solid" buttons (Done/Add/segments) invert: light `#1E2749`/white → dark `#EFECE2`/`#14181F`

Typography:
- UI: **Nunito** (600/700/800/900). Screen titles 20px/900; body 14–15px/800 for labels, 600–700 for secondary; section headers 12px/900, letter-spacing 0.8px, uppercase, muted.
- Receipt & money: **Roboto Mono** (400–700). Receipt lines 13px; amounts always mono.
- Minimum touch targets 40–44px.

Shape: cards radius 16px, inputs 9–12px, pills/chips 99px, phone bg sections spaced with 10px gaps, screens padded 20–24px.

## Screens
(See LOGIC.md for exact behaviour; copy strings are final.)

1. **Home** — logo (soft drop shadow), tagline "Split the bill in seconds.", privacy chip "On-device only · receipts never leave your phone", list of groups (icon monogram, name, "N receipts · M people", total, chevron), "Archived groups (n)" link when any, green CTA "Split a new bill", gear → Settings. Empty state: dashed card "Nothing yet. Scan your first bill."
2. **Where does this bill go?** (Step 1 of 6) — pick an existing group (scrollable list), "+ Start a new group" (inline name input + Create), or "One-off split" (Not part of a group). No "just me" mode — the app always splits.
3. **Who's splitting?** (Step 2) — grid of friend cards (avatar, name, green border + ✓ badge when selected), "+ Add someone new" inline input, count line "N splitting, including you."
4. **Scan the bill** (Step 3) — dark viewfinder with corner brackets and striped receipt placeholder, shutter + Gallery, caption "OCR runs on the phone. Nothing is uploaded." Scanning: animated green scanline + "Reading receipt on-device…" (~1.7s in mock), then auto-advance.
5. **Check the items** (Step 4) — the correction UI, the most important screen per the brief. Balance banner (red "Doesn't add up… Double check the lines." / green "Adds up…"). Receipt-styled card (mono font, dashed rules): tap-to-edit bill name and date (pencil affordances), tappable line rows (suspicious OCR rows highlighted amber), inline editor per row (desc + amount inputs, kind chips **Item / Extra (+) / Discount (−) / Ignore**, "OCR read: …" raw text, trash delete bottom-left, Done), "+ Add an item", printed SUBTOTAL/TOTAL footer.
6. **Who had what?** (Step 5) — one card per split row (items AND extras/discounts) with avatar toggles per member, per-row hint "€X each" / red "Unassigned"; header pill "Split equally" ↔ "Clear all"; CTA turns gold with "Summary · N items unassigned" when incomplete.
7. **This receipt** (Step 6) — navy hero (bill name, party, total), **PAID BY** avatar picker, "Part of {group} · see the group total" chip when in a group, per-person cards (itemised shares, "· ÷N" markers), green **Done**, grey "Share the split · send a message".
8. **Group screen** — name input, members row (Edit), receipts list (title / comment · date / green "Paid by X", amount, ⋯ menu → Edit | Mark as settled/unsettled; settled rows struck + dimmed), "+ Add another receipt", green "Group summary" CTA. Header ⋮ menu: Go to home / Currency (expands to Default + enabled currencies) / Archive this group / Delete (two-tap, fills red on confirm).
9. **Receipt view (read only)** — receipt-styled card: lines (or per-person shares for logged receipts), TOTAL, PAID BY, settled badge, "Edit this receipt".
10. **Group summary** — navy hero (total of unsettled receipts), amber warning "€X on {bill} not assigned to anyone yet. Tap to finish assigning." (tap → step 5), **SETTLE UP · FEWEST PAYMENTS** card (avatar → avatar, "Tom pays Theo", amount, green "Mark paid"), per-person cards with net status ("owe/owes", "get/gets back" in green, "all square"), itemised lines incl. "Paid …" credits and settlement records, "Share the group total". Empty state when all settled.
11. **Archived groups** — list with totals and Restore buttons; rows open the group.
12. **Settings** — YOUR NAME (replaces "You" everywhere), Appearance (Light/Dark segmented), CURRENCIES (managed list: symbol, name, Set default, × remove; "+ Add a currency" from catalogue €, £, $, CHF, ¥, kr, zł, C$, A$), FRIENDS (list, × remove, add input), SECURITY (PIN toggle + Change PIN row), DATA (Clear all data, two-tap, fills red).

## Interactions & behaviour
- Navigation: linear 6-step flow with a real **back stack** (back always returns to the actual previous screen). Every mid-flow screen has a top-right **✕ → "Discard?"** (two-tap, auto-disarms after 2.5s) that abandons the flow and resets the draft.
- All destructive actions are two-tap with the confirm state filled solid red (delete group, clear all data).
- Error feedback is a bottom **toast pill** (navy, red "!" dot, auto-dismiss ~2.8s). Used for: removing a friend with assigned items, removing the default currency, removing a currency a group uses.
- Share = copy-to-clipboard of a plain-text summary (monospace preview in a bottom sheet); no messaging SDKs.
- Screen transitions: 250ms fade-up ease. Toggle/segment changes: 150ms.

## Assets
- `logo.png` — app logo (torn receipt "BI" + green "LL" + euro coin). Render at ~132px on home with a soft drop shadow (`0 8px 18px rgba(28,34,44,.16)`).
- All icons are simple 2px-stroke line glyphs (chevron, gear, kebab, camera/gallery, trash, house, arrow); use Material icons or match the SVGs in the prototype.

## Files
- `Bill Split App.dc.html` — full interactive prototype (all 12 screens, light+dark)
- `LOGIC.md` — complete data model, calculations and edge cases (read this before coding)
- `android-frame.jsx` — presentation bezel only, not part of the design
- `logo.png` — brand asset
