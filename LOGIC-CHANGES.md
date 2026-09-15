# Corrections to the spec

The brief (`receipt-splitter-brief.md`) and the design handoff (`LOGIC.md`) disagree in
three places, and the brief's sample code carries a handful of bugs. This is what was
changed and why. Every item has a test.

## The three conflicts

### 1. `LineKind` had no `discount`

The brief's enum is `item / adjustment / subtotal / tax / total / payment / noise`.
The handoff's correction UI offers `Item / Extra (+) / Discount (-) / Ignore`.

A discount is not a negative adjustment. Receipts print the same 2.00 saving as
`2.00`, `-2.00` and `(2.00)` interchangeably, so the sign OCR reads cannot be trusted.
`LineKind.discount` now exists and its effective amount is `-abs(amount)` whatever was
read. The footer kinds survive because the balance check and the printed footer need
them; the UI collapses them, plus `noise`, onto the single "Ignore" chip, and
`LineKind.uiChoice` makes sure a subtotal row that is opened and closed without being
touched does not quietly become an item.

`lib/parsing/receipt.dart`

### 2. Tax: footer figure, or splittable extra?

The brief classifies tax as a printed summary figure. The handoff calls it an
"Extra (+)" to be split between people. Both are right, for different receipts:

- **VAT already inside the prices** (UK, Ireland, most of the EU): `subtotal == total`.
  Splitting the VAT line would charge everyone their tax a second time.
- **Sales tax added at the till** (US): `subtotal + tax == total`. Not splitting it
  leaves the bill short.

The arithmetic says which, so the parser tests it rather than guessing: when
`|subtotal + tax - total| < 0.02` and the subtotal alone does not match the total, the
tax line is promoted to `adjustment` and gets assigned like anything else. The user can
still override with the kind chips.

`lib/parsing/receipt_parser.dart`, `parseReceipt`

### 3. Discount words were filed under adjustments

`_adjustmentWords` contained `discount`, `voucher` and `off` alongside `tip` and
`service charge`. Split into two lists, feeding the two different kinds.

## Bugs in the brief's code

### `String.contains` matched inside words

`_classify` tested keywords with `contains`. `"coffee".contains("off")` is true, so
**every coffee on every receipt was classified as a discount**. `"cashew".contains("cash")`
is true, so cashews were payments. Keyword tests now match on word boundaries, which
also removes the ordering hazard the brief warned about: `"subtotal"` no longer contains
a matchable `"total"`.

### A leading quantity left its `X` behind

`2 X PERONI 330ML 9.00` took the `2` as the quantity and left the description as
`X PERONI 330ML`. The bare multiplication sign is now taken too.

### `balances` shouts at a receipt it cannot check

The brief's `balances` returns `false` when no subtotal and no total were read, which
puts a red "doesn't add up" banner on a receipt whose subtotal simply was not legible.
`hasBalanceTarget` now distinguishes "wrong" from "nothing to check", and the banner is
hidden entirely in the second case. This is what `LOGIC.md` section 3 asks for.

### Pennies did not add up

`LOGIC.md` section 5 computes shares as exact division rounded at display time, and
notes that person totals may then disagree by a penny. That is not survivable once the
group summary nets people off: if a receipt's shares do not sum to the receipt, the
payer is credited with a different figure from the sum of what everyone owes, and the
invariant that all nets sum to zero breaks.

All division now happens in integer cents with largest-remainder allocation
(`lib/model/money.dart`, `allocate`). A row's shares always sum to the row exactly, so
the nets sum to exactly zero rather than approximately zero. Tested exhaustively for
every total from -5.00 to 5.00 across party sizes 1 to 8.

### Dropping someone from the party lost their share

`LOGIC.md` section 4 says removing someone does not clean up assignments, and section 5
says shares are computed over party members only. Taken literally that loses money: a
row split three ways with one person gone would distribute two thirds and drop the rest.
Non-members are now filtered out *before* the division, so the remaining two owe half
each and the row stays fully distributed.

## Things the prototype deferred

- **Logged receipts are editable.** The prototype froze a receipt on completion and
  showed a toast if you tried to edit it. A `Receipt` now keeps its lines and
  assignments, so any receipt reopens into the same flow and writes back to the same id.
  Settlement records still stay frozen, so a later edit surfaces as a residual transfer
  rather than rewriting history.
- **Settlements can be undone** (`undoSettlement`).
- **Adding a receipt to a group pre-selects that group's members** rather than starting
  from an empty party.
- **Price-column filter** (brief section 12, "do it first"): the median right edge of
  the candidate amounts defines the price column, and money-shaped tokens far from it
  are rejected. This is what stops dates and phone numbers becoming prices.
- **Multi-line items and weighed rows** (brief section 12) are folded into the line
  above.

## UI fixes found by rendering at phone width

Screenshot tests at 360px surfaced four layout bugs, all fixed and all covered by
`test/screenshot_test.dart`:

- The logo's drop shadow was a `BoxShadow` on a container, which paints a rectangle and
  ignores the artwork's transparency. It is now a blurred, tinted copy of the image.
- A green selection ring around a friend whose colour *is* the brand green was
  invisible. Avatars now carry a gap ring.
- The "You" avatar is the light theme's ink navy, which all but disappears on a dark
  card. Avatar colours are now nudged away from their background when the contrast is
  too low.
- Long labels overflowed the ghost buttons and section headers.

## Second pass: matching the prototype

The first build followed the written handoff but diverged from the prototype's actual
inline styles in ways that changed the feel of the app. Read out of
`Bill Split App.dc.html` and corrected:

- **Home** is bottom-weighted. The logo, a 24px/900 headline (not a small muted
  subtitle) and the privacy chip sit at the top; a flexible spacer pushes the group
  list and the call to action to the bottom of the screen.
- **Primary buttons** are 17px/900 on a 16px radius with 17px padding, not 15px/800 on
  an 11px radius.
- **Screen subtitles** are uppercase, 11px/800, 0.6 letter-spacing: `STEP 2 OF 6`, not
  `Step 2 of 6`.
- **Back** is a thin chevron in a 40px circle, not Material's arrow.
- **The people grid** is two columns of horizontal chips (avatar, then name) with the
  tick badge floating off the corner, not three columns of vertical cards.
- **Add affordances** are dashed outlines throughout: new group, new friend, add an
  item, add another receipt. They were solid grey buttons.
- **The receipt card** centres its name and date in mono with a faint pencil beside
  each, rather than left-aligning them.
- **Scan** uses a 76px ring shutter with a 58px core, a 46px rounded-square gallery
  button with its label underneath, and a striped receipt rotated 3 degrees.
- **"Split equally"** is a tinted pill in the header, not a control in the body.
- **The receipt hero** is a compact row with the total on the right, not a tall stack.
- **Paid by** is one row: label left, avatars right.
- **The group menu** is a floating popup anchored under the kebab, not an inline card.
- **Settings** uses hairline-divided list cards, monospace currency tiles, a pill
  switch and round grey remove buttons.
- **The navy hero stays navy in dark mode**; it is hard-coded in the prototype rather
  than themed.

Two bugs found only by rendering at 360px and one by inspecting the built APK:

- `✕` (U+2715) is not in Nunito and drew as a tofu box. It is an icon now.
- The settle-up row could not fit two names, an amount and a button on one line, so the
  amount now sits under the label rather than a name being truncated.
- **The release APK requested `INTERNET`.** The `camera` and `image_picker` plugins
  merge their own permissions into the manifest, so the shipped app quietly had network
  access, `ACCESS_NETWORK_STATE` and `RECORD_AUDIO` — directly contradicting the whole
  premise. All three are now removed with `tools:node="remove"`, verified with
  `aapt2 dump permissions`.

## Demo data removed

The app used to seed a Lisbon trip and a Trattoria Bella receipt on first run. It now
starts empty. That content moved to `test/fixtures.dart`, where the tests and the
screenshot suite build it themselves.

## Receipt payment progress

"Mark paid" on the group summary records a payment from one person to another.
Receipts now show how far they have been paid off as a result: a green **Paid** badge,
or an amber **Part paid · 2/3**.

The rule needs stating because the obvious one is wrong. Settle-up clears *net*
positions, not individual bills: a single payment can cover parts of three receipts,
and somebody who paid for the taxi has that set against what they owe for dinner. So
matching payments against each bill's gross debts gets the wrong answer — the payment
is smaller than the gross debt by whatever the payer is owed elsewhere, and bills that
are fully settled still read as short.

What is asked instead is: does this person still owe the group anything? Whatever they
owed that is no longer outstanding is credited to their bills oldest first, which is
the order people assume debts clear in. Clear every transfer and every bill reads Paid.

Two consequences worth knowing:

- A bill can show **Part paid** before anybody hands over money, when debts cancel out.
  If you paid for dinner and Amara paid for the taxi, part of what she owes you is
  already settled by what you owe her. That is what the group summary already says; the
  badge now agrees with it.
- The badge is **display only**. It deliberately does not mark the receipt settled or
  drop it from the group aggregation. The settlements have already cancelled those
  debts in everyone's net, and excluding the receipt as well would subtract the same
  money twice and break the invariant that the nets sum to zero.

"Mark as settled" on a receipt remains a separate, manual statement that a bill no
longer counts at all, and still overrides the derived badge.

## Undoing a settle-up

Recorded payments are listed under **Payments recorded** on the group summary, each
with an **Undo**. Undo removes that specific record — matching the amount as well as
the two people, so undoing one of several payments between the same pair takes back the
one that was tapped — and the debt returns exactly as it was.

## Running total while editing

The correction screen shows what the lines currently add up to, broken out into items,
extras and discounts, against what the receipt says. It updates on every keystroke
rather than on Done, so the figure converges while you type. Tapping a row also scrolls
the editor to the top of what is left of the screen, so it stays above the keypad, and
the screen's own call to action is hidden while a row is open to buy back the space.


## Transcription

The parser now repairs prices that OCR misread, in three tiers, each assuming
a little more than the last:

1. Tokens that are unambiguously money.
2. Characters that can only be digits in that position — O for 0, l and I for
   1, S for 5, B for 8 — and currency symbols read as letters, so "9.SO"
   becomes 9.50 and "C2.15" becomes 2.15.
3. A decimal point the printer or the camera lost, so "185" becomes 1.85. This
   one runs only inside an established price column, because outside it a bare
   run of digits is far more likely to be a loyalty number or a date.

The tiers matter because locating the price column and reading damaged prices
depend on each other: a receipt whose prices are all slightly misread has no
clean candidates to find the column from. Tier two often supplies exactly the
evidence the column needs, so the column is recomputed between tiers.

A row holding two prices is two printed lines that a crease pushed together.
Each price seeds a line and every word joins whichever price it sits nearest
to vertically, which recovers both the amount and the two descriptions.

`test/ocr_corpus.dart` holds seven receipts built from geometry rather than
text — clean, garbled, missing separators, creased, merged, skewed, and a
supermarket slip with a weighed item and a loyalty number. `test/ocr_false_positive_test.dart`
holds the other half of the job: phone numbers, dates, table numbers and
loyalty cards that must not become prices.

## Settling a bill and marking a payment now agree

These were two separate mechanisms that contradicted each other.

"Mark as settled" on a receipt excluded it from the group's sums. "Mark paid"
on a settle-up transfer recorded a payment. Used together they double-counted,
and in the worst order they inverted the group: with a €30 dinner split three
ways and everybody square after paying, marking the bill settled left the
payer owing €20 and the other two owed €10 each.

The cause is that excluding a receipt removes its debts, but the payments that
already cleared those debts stay in the ledger.

There is one ledger now. Marking a bill settled **records the payments that
clear it** — one entry per person who still owes something on it, tagged with
the receipt — rather than hiding the bill. Aggregation counts every receipt,
settled or not. The consequences:

- Whichever is done first, the second finds nothing left to clear.
- Settling a bill somebody has already part-paid records only the remainder,
  so nobody is charged twice.
- Unsettling removes what settling recorded, and leaves alone any payment
  somebody actually made through settle-up.
- The nets still sum to exactly zero at every step, in every order.

The `settled` flag survives, but it now decides one thing only: whether the
bill still counts towards what the group has spent.

Receipts marked settled by an earlier build carry no ledger entries, so their
debts would reappear on upgrade. They are migrated on first load: the payments
that cleared them are written down once, and the file is saved back.

## Deleting a line

The confirmation before a swipe-delete is gone. The swipe is deliberate
enough, and a modal for every line made correcting a receipt tedious.

## One way to clear a debt

"Mark as settled" is gone. There were two mechanisms for saying a bill had
been paid off and they could not be reconciled:

- **Mark as settled** on a receipt cleared it by excluding it from the sums.
- **Mark paid** on a settle-up transfer recorded a payment between two people.

The first attempt at fixing this kept both and had settling a bill record the
payments that clear it, tagged with the receipt. That removed the inversion
but left a subtler fault: payments are attributed to bills oldest first, so a
payment tagged to a *later* bill was credited to an *earlier* one on the next
recalculation, and the wrong receipt showed as paid.

The honest fix is that there is one mechanism. A debt is cleared by recording
a payment from one person to another, and nothing else. The `settled` flag is
gone from the model, from storage and from the interface. A receipt reads as
**Paid** or **Part paid** when the people who owe on it have covered it, which
is worked out rather than declared.

Data written by an earlier build is migrated on first load: a receipt that was
marked settled has the payments that cleared it written down once, so it stays
settled rather than having its debts reappear.

The receipt's menu is now **Edit** and **Delete**. Deleting a receipt had no
route in the interface at all before this, despite the state layer supporting
it; it asks for confirmation, unlike deleting a line, because it cannot be got
back.

## Totals are what is still owed

The group and home screens led with what the group had spent, so a trip where
everybody had settled up still showed a large number as though money were
outstanding.

They now lead with what is still to be handed over — the sum of what everybody
owes, after the payments recorded so far — and say "All square" when that is
zero. The amount spent moves to the subtitle: "3 receipts · €164.20 spent".

## The maths, gone over properly

`test/settlement_maths_test.dart` covers, with the invariants checked after
every step:

- a bill the payer covered alone; one debtor and one creditor; several of each
- debts between two people that cancel without anybody paying
- money nobody has claimed
- a discount larger than the item it applies to, leaving somebody owed money
- somebody dropped from the party after being assigned items
- part payments, overpayments, payments nobody owed, and refusing an empty or
  negative one
- a new bill added after everything was settled, which must not bring the old
  debts back
- editing a paid bill, which reopens only the difference
- deleting a paid bill, which leaves the payment standing so the payer is owed
  it back
- undoing a payment
- rounding: a tenner three ways, a penny three ways, and awkward amounts
  across two to four people
- six hundred randomly generated groups, settled one payment at a time, with
  the books checked at every step
- three thousand random net positions through the settle-up algorithm

The invariants asserted throughout: the nets sum to exactly zero; the suggested
payments clear every debt exactly; no transfer is empty or to oneself; the
outstanding figure equals what is still owed; there is something outstanding if
and only if there is a payment to make; and recording a payment reduces what is
outstanding by exactly that amount and disturbs nobody else.

## Editing a bill that already exists saves as you go

Opening a saved receipt put a copy in the draft, and only writing that draft
back at the end of the flow saved anything. Tapping the amber "not assigned to
anyone yet" banner, assigning the forgotten item and then pressing back —
which is the natural thing to do, since you came from the group summary — threw
the change away silently. The money stayed unaccounted for and the totals never
moved.

A bill that already exists is now written through as it is edited. The draft
keeps a copy of the receipt as it was, so the two-tap discard still puts it
back exactly. A bill being *created* is unchanged: it joins the group when the
flow finishes, not before.

## Settling up is refused while money belongs to nobody

If part of a bill is unassigned, every figure under it is an underestimate:
the shares do not add up to the receipt, so the nets are short. Recording
payments against those figures bakes the mistake in, and the shortfall
reappears the moment the item is assigned.

While any bill in the group has something unassigned, the settle-up amounts
are shown but **Mark paid** is inert and says why. The amber banner above it
already says which bill and how much, and tapping it goes straight to the
assignment screen.

## A badge is a claim that money moved

Bills were reading **Part paid**, and sometimes **Paid**, on groups where
nobody had handed over a penny.

The arithmetic behind it was not wrong. If Ben owes fifty for the dinner Ana
fronted and put thirty on the taxi himself, thirty of his dinner debt really
is gone — the two amounts met in the middle. That is offsetting, and it
belongs in the sums. What it is not is a *payment*, and badging it as one told
the group that money had changed hands when none had.

The per-receipt ledger now counts the two separately: everything no longer
outstanding, and the part of it somebody actually handed over. A badge needs
the second. The one exception is a group where everybody is square, which is
paid off however it got there.

## What each person actually had

The group summary gave one figure per bill per person and left everyone to
take on trust that it was not the total divided by the number of people at the
table. Each bill now opens into the items behind it, with `÷N` where a row was
shared — which is the part that does the work, because it distinguishes a
quarter of a shared bottle from a quarter of the bill.

## Money held for a bill that is no longer there

Payments are frozen on purpose: a payment is a thing that happened, and an app
that quietly rewrites it when a bill changes is lying about the past. That was
the flaw in the old *mark as settled* flag, which could disagree with the
payments and did.

The cost is that deleting or shrinking a bill somebody has settled leaves them
holding money for a debt that has gone. The answer is still arithmetically
right — if Ben paid fifty towards a bill that never existed, he is owed fifty
back — but the balance used to move with nothing to explain it.

So the residue is named rather than absorbed, and the question is put at the
moment the user has the context to answer it. Deleting such a bill now says
who has settled against it and how much, and offers to hand the money back in
the same action. A refund is itself a payment, in the opposite direction, back
to whoever actually received the money — nothing is edited or removed, so the
ledger stays append-only, which is the only reason its figures can be trusted.

Where it arises some other way — editing a bill down rather than deleting it —
the person's card on the group summary says so, and offers the same way out.

## A bill with no receipt

Not every bill comes with a receipt. It was lost, it was never issued, or the
evening is being reconstructed a day later. **Type it in**, beside the shutter,
starts an empty bill and goes straight to the same check screen a scan lands
on, so everything after that point is identical. The draft remembers that it
was typed rather than photographed, because "nothing was read from this photo"
is nonsense about a bill that was never photographed.

## Deleting a paid bill, properly this time

Two things were wrong, and only one of them was arithmetic.

**The warning described the wrong thing.** It named the people who had
"settled against this bill". Nobody ever settles against a bill: a payment
clears a net position across the whole group. The sentence claimed a precision
the ledger does not have, and it described only the people left holding money
— saying nothing about the person who fronted the bill losing the credit for
it, which is usually the biggest movement on the screen. In a three-bill group
where everybody was square, deleting one bill moved the payer from square to
owing twenty and the warning did not mention them at all.

So the dialog now answers the question actually being asked — *what will this
do?* — for everyone it touches, worst movement first, and says which of the
two buttons the figures describe, because handing the money back changes them
again.

**And deleting a second bill reversed the same payment twice.** Each refund
pass walked a person's payments from the newest and took what it needed, with
no memory of what an earlier pass had already handed back. After two
deletions the newest payment had been reversed twice over: money went back
from whoever happened to be newest rather than from whoever was actually
holding it, and somebody ended up having returned more than they were ever
given. A pass now subtracts what has already come back from each person
before deciding how much of a payment is still reversible.

Two further corrections fell out of testing that:

- A refund is now marked as one. It counts identically in every sum, but the
  screen can say *handed back* instead of showing a column of identical ticks
  pointing both ways, and a reversal can never itself be reversed.
- Overpayment was measured as everything a person had paid out less everything
  that came in. That counted money they had *returned* as money they had
  *paid*, so somebody who handed a refund back looked as though they had
  overpaid — and the app offered to refund them money they had never paid.
  What a person is out of pocket is what they handed over to clear a debt,
  less everything that has come back to them, whichever direction it came
  from.

Two fuzzers hold this down: two hundred groups deleted bill by bill, checking
at every step that the figures promised by the warning are the figures that
result, that nobody has handed back more than they were given, that the nets
still sum to zero, and that a group with every bill deleted ends square.

## What the full check turned up

An eighty-five agent audit across eight lenses, plus an invariant suite run
against deliberately hostile data. Between them they found eleven real
defects. The ones that mattered:

**The PIN did not lock anything.** The lock was expressed as `MaterialApp`'s
`home:`, which is only the bottom of the navigator stack. Anything pushed on
top of it — a group, a receipt, the summary with every figure in it — stayed
on screen when the app re-locked, so the PIN blocked the app only if you
happened to be on the home screen when you put the phone down. It is now an
overlay above every route, with the screens beneath it offstage: not painted,
not hit-tested, not read out. Unlocking returns you to where you were.

**A failed read looked exactly like a first run.** The store loader swallowed
every error and returned null, which the app took to mean "nothing saved yet".
It seeded itself empty and the next save wrote that emptiness over the top.
Errors now propagate, a read that fails or hangs sets the store unavailable,
and while it is unavailable nothing is written at all. Saving also goes
through a temporary file and a rename, so a process killed mid-write leaves
the previous store intact rather than a truncated one.

**Clear all data did not.** The copies kept of stores that could not be parsed
— each a complete dump of the receipts, the names and the PIN hash — were left
in the documents directory, and accumulated one per failed parse.

**Amounts of a thousand or more were not money.** The pattern deciding whether
a token is a price required a thousands separator, so "1200.00" as most tills
print it was read as text. The villa, the flight and the bill's own total all
vanished, which is the worst possible line to lose.

**A supermarket weighed row lost its price.** Any row containing "@" was
folded into the line above. That is right for "0.482 kg @ 4.98/kg" printed
under an item, and wrong for "BANANAS 1.2kg @ 1.50" with what it came to on
the right — which threw the item away and gave its money to whatever was
printed before it, often the shop's own name.

**Pasting "Infinity" into an amount crashed the screen.** `double.tryParse`
accepts it, and rounding it threw during layout. Amounts are now always finite
and within a sane range, from the keypad and from a misread photo alike.

**A bill paid in cash stopped saying so** as soon as the same person fronted a
later bill — a fault in the badge work earlier in the day. It inferred what
somebody had handed over by differencing their whole-group net; that reads the
right number only while they are still in debt. What a person paid is a fact
about the payments, not about where the group stands afterwards.

**The refund button moved more money than it named**, sweeping up overpayments
the user had already been offered and declined. **It also asked the wrong
person.** Reversing the most recent payment is not the same as reversing the
one that is now unowed: pay Ben for the taxi on Monday and Cara for dinner on
Tuesday, delete the taxi, and Cara was told to hand money back while Ben kept
it. The ledger already knows who is holding money they are not owed — they
have a positive net — so that is who is asked now.

**Undoing a payment that had been refunded** left the refund behind as a
one-way transfer, inventing a debt between two people over a bill that no
longer existed. Undoing a payment now takes its refund with it.

Two more that were only visible on a device: the lock screen's keypad was
clipped off the bottom in landscape, so a locked app could not be opened
without turning the phone; and the "adds up" tick was U+2713, which neither
bundled font contains, so it drew as an empty box. There is now a test that
reads the fonts' character tables and fails on any character the app draws
that they do not contain.
