# Outstanding

## Rules that are wrong or incomplete

- **`no-shared-fixtures` matches a filename, not contents.** It fired on a file
  called `Fixtures.swift` that held `pid()`, `usd()`, `item()` — parameterised
  factories, i.e. builders already. The advice ("replace it with builders") was
  wrong for a file that was builders. It should look for stored `static let`
  members, which is what a shared fixture actually is, and say "the name
  misleads" otherwise.
- **No rule checks that `.product(name:package:)` names a declared package.**
  While fixing the reference project I added a product reference without the
  corresponding `.package(path:)`. The manifest was invalid; keystone-swift
  said nothing, because product resolution searches every package in the repo
  rather than the ones this manifest declares.
- **`imports-are-declared` only applies to SwiftPM.** Xcode's implicit target
  dependencies are not written down anywhere readable.

## Missing concepts

- **`testSupport` role.** Sharing test doubles across packages needs a regular
  `.target` published as a library — a test target cannot be shared across
  packages (SwiftPM dies with an internal error). Such a target must be
  reachable only from tests, which needs a reverse constraint: `visibleTo`, the
  inverse of `mayDependOn`. Without it, `composition` (which may depend on
  anything) could link test doubles into the shipping app.
- **Per-rule options.** Rules take a severity but no parameters. SwiftLint's
  `line_length: warning: 120` shape is worth copying for things like
  `test-pyramid`'s tolerance and `peer-consistency`'s threshold, which are
  currently global.

## Borrowed from SwiftLint, not yet done

- ~~**Reporters.**~~ Done: `--reporter xcode` matches the diagnostic format
  every Swift editor already parses, and `--reporter github` annotates the
  changed lines of a pull request. SARIF, for GitHub code scanning, is still
  open.
- **`--strict`.** Treat warnings as errors, for projects past the migration.
- **`--fix`.** Several rules know the destination already — `declaration-placement`
  computes it — so moving the file is mechanical. This is the biggest lever for
  the migration story and the one most likely to be got wrong.
- **A rule reference.** Every identifier documented with its rationale and
  citation, rather than only in source comments.

## Documentation

- **The README predates the zero-config pivot.** It still describes `init` as a
  prerequisite and shows `paths` in the configuration example. Layout is now
  derived from the repository; a manifest exists only to state a severity, a
  rule selection, or a layout too unusual to read.

## Overlap with SwiftLint

Measured, not assumed: of 256 SwiftLint rules and 29 here, exactly one is the
same rule — `todo` and `no-todo`. `no_grouping_extension` is a partial subset of
`no-extensions`, catching only the same-file case. There is nothing worth
delegating, and `no-todo` is the one rule to consider dropping in favour of
SwiftLint's, which is better integrated.

## Unverified

- **The Kiro hook schema.** It varies by version and I could not confirm the
  shape. The steering file works regardless; the hook may need adjusting.
- **CI needs a PAT** (`KEYSTONE_SWIFT_TOKEN`) while this repository is private.

## In the reference project

Left deliberately, as judgement calls rather than mechanical fixes:

- **12 missing snapshot suites.** Needs `swift-snapshot-testing` added to each
  UI package and a simulator run to record references. The images cannot be
  faked: a suite with nothing committed writes its reference every run and
  compares it against itself, so it is green and has never been able to fail.
- **13 duplicated test doubles**, chiefly `StubGetSession` (×10) and
  `StubObserveSession` (×8). Fixing them is the `testSupport` question above —
  either accept the copies as the price of independent test targets, or give
  the shared need a home.
- **17 peer discrepancies.** Mixed. `OnboardingUI`, `SheetUI` and `SnackbarUI`
  having no tests at all looks real; `Money` having no `Data/` or `DI/` looks
  deliberate, since it is a pure value-object package, and wants
  `consistency.ignore`.
- **6 inverted pyramids.** `StockAlert` is the worst at 27 acceptance tests to
  13 unit tests.
