# Wiring up the tests

These XCTest files (`BankTemplatesTests.swift`, `RegionDetectorTests.swift`)
need a Unit Testing Bundle target in Xcode. I left them out of `project.pbxproj`
because the schema for a test target involves a lot of moving pieces (its own
build configuration list, host-application setting, scheme entry, etc.) and
hand-editing it from outside Xcode is fragile.

## Three-click setup

1. In Xcode, **File → New → Target…**
2. Choose **Unit Testing Bundle**. Name it `ExpenseTrackerTests`. Set
   _Project_ = `ExpenseTracker`, _Target to be Tested_ = `ExpenseTracker`.
3. When Xcode creates the target, it adds an empty `ExpenseTrackerTests.swift`
   file inside a new `ExpenseTrackerTests` group. Delete that placeholder file
   (move to trash), then **drag** `BankTemplatesTests.swift` and
   `RegionDetectorTests.swift` from this directory into the new group. In the
   "Add to target" sheet, tick **only** the `ExpenseTrackerTests` target.

That's it. **⌘U** runs the suite.

## What they cover

- **`BankTemplatesTests`** — one fixture per region pack, verifying amount,
  currency, and bank attribution. Plus two registry invariants: every region
  in the catalog has at least one template, and template IDs are unique.
- **`RegionDetectorTests`** — `RegionStore` round-trip, the 70%-threshold
  mismatch heuristic, and the snooze. The auto-detector itself reads global
  state (`Locale.current`, `TimeZone.current`, `CTCarrier`) so its logic is
  exercised through the picker rather than unit-tested in isolation.

## Adding more fixtures

The seed fixtures here were derived from public format conventions, not real
customer messages. As you collect real samples:

1. Pop them into the matching `testRegion…` function (or a new one).
2. Use the `assertTxn` helper — it checks amount/currency/type and optionally
   the template ID. If you assert `templateId`, a regex tweak that breaks the
   match will be caught immediately.
3. If a real sample lights up a corner case, add it under a name like
   `testRegion…RealSample01` so it's traceable.

## A note on ordering

Tests use `RegionStore.set(...)` to force the active region inside each test.
That's stored in App Group defaults, so a test left in a non-default region
would leak into the next one. The detector tests reset state in `setUp` and
`tearDown` for that reason — keep that pattern when you add tests.
