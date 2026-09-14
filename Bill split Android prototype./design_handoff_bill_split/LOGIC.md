# LOGIC.md — complete behavioural spec

Everything the prototype computes, with edge cases. Amounts are decimal currency values; the prototype stores entered amounts as strings and parses them (comma or dot decimal separator accepted; unparseable → 0).

## 1. Data model

```
Friend    { id, name, color }                      // id 'you' is the current user, never removable
Group     { id, name, currency: string|null,       // null = follow app default currency
            archived: bool,
            receipts: Receipt[],
            settlements: [{from, to, amt}] }       // recorded settle-up payments
Receipt   (logged)   { id, name, sub (comment · date), total, paidBy: friendId,
                       per: {friendId: shareAmt},  // per-person shares; sums to total
                       settled: bool }
Receipt   (live/draft) { billName, billDate, paidBy, items: Line[], assign: {lineId: friendId[]} }
Line      { id, desc, amount, kind: 'item'|'adjustment'|'discount'|'noise',
            raw (OCR text), sus (suspicious flag), custom (added by hand) }
Settings  { myName, dark, appCurrency, currencies: string[], pinOn }
```

The prototype has ONE live draft receipt at a time; production should persist each finished receipt into its group as a logged Receipt (freeze name/date/total/per/paidBy at completion).

## 2. Line kinds & effective amounts

- `item` — a purchased thing; split between assignees.
- `adjustment` — "Extra (+)": tip, tax, service charge. Split between assignees like an item (NOT proportionally — the user chooses who shares it).
- `discount` — "Discount (−)": effective amount is **always negative**: `eff = -abs(amount)` regardless of the sign OCR read. All other kinds: `eff = amount`.
- `noise` — ignored everywhere (struck through in the check screen only).

`splitRows` = lines with kind item|adjustment|discount → these are what appear on the assign screen and in all sums.

## 3. Balance check (Check the items screen)

- `itemSum` = Σ amount of kind **item only** (not extras/discounts).
- Compared against the **printed subtotal** parsed from the receipt (mock: €47.00; printed total €51.70).
- `balanced` iff `|itemSum − printedSubtotal| < 0.02` (tolerance absorbs rounding, not errors).
- Red banner when unbalanced: "Doesn't add up. Items total {X} but the receipt says {Y}. Double check the lines." Suspicious OCR rows (`sus`) get an amber background; any user edit to a row clears its `sus` flag.
- Green banner when balanced: "Adds up. Items match the printed subtotal {Y}."
- Edge: if OCR found no subtotal, fall back to printed total; if neither, hide the banner (per the original brief `balances` is false when target is null — don't show a false negative).

## 4. Assignment (Who had what?)

- Each split row holds a set of member ids. Toggling avatars adds/removes.
- Row hint: `eff/N each` when N ≥ 1; red "Unassigned" when N = 0.
- "Split equally": assigns EVERY split row to ALL current party members. When every row already contains every member, the same button becomes **"Clear all"** and empties every row's set.
- CTA: green "See the summary" when all assigned; gold "Summary · N item(s) unassigned" otherwise (never blocks).
- Edge: removing a friend from the party (people step) does NOT auto-clean assignments; shares are computed only over party members (see §5), and Settings blocks deleting a friend who appears in any assignment set (toast: "Can't remove {name}. They still have items on a bill.").

## 5. Per-receipt shares (live receipt)

For each party member P:
```
share(P) = Σ over split rows r where P ∈ assign[r]:  eff(r) / |assign[r]|
```
- Unassigned rows contribute to nobody (see §7 for the group-level warning).
- `grand` (receipt total shown) = Σ eff over ALL split rows — i.e. includes unassigned rows.
- Display: lines carry "· ÷N" when N > 1. Discounts appear as negative shares.
- Rounding: shares are computed exact and formatted to 2dp at display time; person totals may differ from each other by ≤ €0.01 total. Do NOT force-reconcile pennies in the prototype's manner; in production prefer largest-remainder allocation if exact pennies matter.

## 6. Paid-by

- Every receipt has exactly one payer (`paidBy`). Live receipt: chosen on the summary screen (avatar picker, default 'you'). Logged receipts store theirs.
- Payer must be a group/party member.

## 7. Group aggregation (Group summary)

Only **unsettled** receipts count. For each person P, accumulate:
```
share(P) += receipt shares          (live receipt: §5 shares; logged: receipt.per)
paid(P)  += distributedTotal        if P is the receipt's payer
```
**Critical invariant:** the payer is credited only with the receipt's *distributed* total (Σ of its shares), NOT its face total. For logged receipts these are equal (per sums to total). For the live receipt they differ while items are unassigned — crediting the face total would make nets not sum to zero.

Then apply recorded settlements (§8), and:
```
net(P) = share(P) − paid(P)
net > 0  → "owes"  (second person: "owe" for You)
net < 0  → "gets back" (green)      |net| shown
|net| ≤ 0.005 → "all square"
Σ net(P) = 0 always.
```

- Hero total = Σ face totals of unsettled receipts (this INCLUDES unassigned amounts — it is "what the group spent", not "what is distributed").
- **Unassigned warning:** if the live receipt is in the group, unsettled, and `grand − Σ livePer > 0.01`, show the amber tappable banner "{€X} on {bill} not assigned to anyone yet. Tap to finish assigning." → navigates to the assign step. This explains the hero-vs-cards gap.
- Empty state when no unsettled balances exist: "All bills are marked as paid up. Nothing owed."

## 8. Settle up (fewest payments) & marking debts paid

- Debtors = people with net > 0.005; creditors = net < −0.005. Sort both descending by magnitude, greedily match: `pay = min(debtor.remaining, creditor.remaining)`, emit transfer, decrement both, advance whichever hits < 0.005. Produces ≤ (D + C − 1) transfers.
- Each transfer row: "{From} pays {To}" ("You pay …" for the user) + amount + **Mark paid**.
- **Mark paid** appends `{from, to, amt}` to `group.settlements`. Its effect on the next computation: `paid(from) += amt` (line "Settled up with {To}: −€amt") and `paid(to) −= amt` (line "Received from {From}: +€amt"). Nets rebalance, the transfer disappears, invariant Σnet = 0 holds.
- Edge: settlements are amounts frozen at mark time. If the underlying bill later changes (re-edit, re-assign, un-settle a receipt), residual transfers reappear for the difference — that is intended behaviour, do not delete settlement records.
- No undo in the prototype; production should offer one (delete the settlement record).

## 9. Settling whole receipts

- Receipt ⋯ menu → "Mark as settled" (toggle). Settled receipts: stay listed (struck through, 55% opacity, "· settled" in sub), excluded from group hero total, group aggregation, home/archived totals, and the unassigned warning. "Mark as unsettled" reverses everything.
- Distinct concept from §8: receipt-settled = "this bill's stakes were cleared"; settlement records = "a person paid their net debt".

## 10. Currency

- Settings holds an enabled-currency list (default €, £, $; catalogue adds CHF, ¥, kr, zł, C$, A$) and one **default** among them.
- Each group may override (group ⋮ menu → Currency: Default | enabled symbols). `currencyFor(group) = group.currency ?? appDefault`. One-off receipts use the app default.
- Formatting: `−?SYM + abs(amount).toFixed(2)` (symbol before number, minus sign leading, e.g. `−€40.00`).
- Guards (toast, action refused): cannot remove the default currency ("Set another currency as default first."); cannot remove a currency any group uses ("\"{group}\" still uses {sym}."). Note: the prototype does NO conversion — a group currency override relabels, it does not convert. Production should either keep that behaviour (label-only, document it) or add rates.

## 11. Friends & profile

- 'you' is always in the party and undeletable. YOUR NAME setting replaces "You" in avatars/cards/share text (verbs adjust: "You owe/get back" vs "{Name} owes/gets back").
- Adding a friend (people step or Settings): trimmed non-empty name, color assigned round-robin from the palette, auto-selected into the current party.
- Deleting: blocked while present in any assignment (toast, §4). Otherwise removed from friends and current selection. Historical logged receipts keep their per-ids; render unknown ids as "?" rather than crashing.

## 12. Groups lifecycle

- Created from the destination step (inline name → immediately becomes the flow's target) or implicitly as a one-off (single-receipt group).
- Rename inline (name input). Archive (⋮ menu): hidden from home list and destination picker, shown under "Archived groups (n)" with Restore; archived groups remain openable.
- Delete: two-tap confirm (fills red), removes the group permanently.
- Deleting/archiving never touches friends or settings.

## 13. Flow control

- Steps: 1 destination → 2 friends → 3 scan → 4 check → 5 assign → 6 summary. Back = pop the navigation history stack (not a fixed order — e.g. reaching Check from a group's "Edit this receipt" backs out to the receipt view, not to Scan).
- ✕ on steps 2–6: first tap arms ("Discard?"), second within 2.5s resets the draft (items, assignments, bill name/date, payer) and returns home.
- Scan is simulated (1.7s) in the prototype; production wires the camera + ML Kit per the brief.

## 14. Share texts (clipboard)

Single receipt:
```
BILL · {billName} · {billDate}
Total {grand} · {N} people
{Paidby implied by summary lines}
{Name} owes {total}            (or You owe …)
  · {line}: {amt}              (one per share line)
Split with BILL · receipts stay on the phone
```
Group:
```
BILL · {group} · {N} receipts
Total {unsettledTotal} ({k} settled)      ← suffix only when k > 0
{Name} owes/gets back {…} | is all square
  · {receipt}: {amt} / Paid {receipt}: −{amt} / Settled up with …
Settle up:
  {From} pays {To}: {amt}
Split with BILL · receipts stay on the phone
```
Sharing = copy to clipboard; user pastes into SMS/WhatsApp/Signal.

## 15. Security & data

- PIN toggle (mock): production should gate app open with a 4-digit PIN (local only), plus Change PIN flow.
- Clear all data: two-tap (fills red), wipes groups, receipts, friends (back to seed 'you'), keeps appearance. "There is no cloud copy to restore." — storage is local-only by design.

## 16. Known prototype simplifications (do differently in production)

- One live draft receipt shared by all entry points; finishing a flow should persist it into its group and reset the draft.
- Logged receipts are view-only ("Edit this receipt" on them shows a toast); production should make them fully editable (which re-opens §7/§8 recalculation — settlements stay frozen).
- "Add another receipt" jumps straight to Scan with the group preselected.
- No persistence: state resets on reload. Production: sqflite/JSON per the brief.
- OCR correction extras from the brief not yet in the UI: merge/split rows, bounding-box overlay on the photo, price-column median filter — see brief §11–12.
