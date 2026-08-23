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

- ~~**`testSupport` role.**~~ Done, along with `visibleTo` — the inverse of
  `mayDependOn`, needed because the layer most in need of stopping is the
  composition root, which may depend on everything by definition.
- **Per-rule options.** Rules take a severity but no parameters. `test-pyramid`
  and `peer-consistency` now carry their own tolerances in `tests` and
  `consistency`, but there is no general shape for it, so the next rule that
  needs one will invent a third place to put it.

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

Down from 26 errors and 59 warnings to **12 and 19**, with no manifest at all.
Build succeeds; all fourteen affected test schemes pass. What is left:

- **12 missing snapshot suites.** Needs `swift-snapshot-testing` added to each
  UI package and a simulator run to record references. The images cannot be
  faked: a suite with nothing committed writes its reference every run and
  compares it against itself, so it is green and has never been able to fail.
- **11 duplicated test doubles**, down from 13. `SessionTestSupport` took the
  two worst — `StubGetSession` written ten times over, `StubObserveSession`
  eight — and the same treatment would clear the rest: `StubCatalog`,
  `StubNavigation`, `SpySnackbarPresenter` and the others each belong to the
  component whose protocol they stand in for.
- **No pyramid findings.** The rule is now off unless a project names an order:
  this project's tiers do not differ in cost, so counting them measured nothing.
- **2 peer discrepancies**, both worth a look rather than an exemption:
  `Product` has no `Sources/Data/*Store.swift` and `SearchHistory` has no
  `Sources/Data/DTO/`, where six of the seven packages built the same way do.

`ProductActionsUIAcceptanceTests` is flaky — it failed once and passed on three
further runs, including one against the committed tree with every change
stashed. Not caused by this work, but worth knowing about.
