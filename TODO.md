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

**Clean.** `✓ 349 files, no violations`, from twenty-six errors and fifty-nine
warnings. Every UI package has a snapshot suite with its references committed;
doubles that two suites share live in a `TestSupport` module belonging to
whichever package owns the protocol they stand in for.

The one manifest in the repository holds three exemptions and the reasons for
them — `Product` keeps no store because its catalogue is fetched rather than
persisted, `SearchHistory` no DTO because it never crosses a wire, `Session`
groups its stores in subfolders because it has eight data files where its
neighbours have two to four. That is a decision record, which is what a manifest
is for; the layout is still read from the repository.

`ProductActionsUIAcceptanceTests` is flaky — it failed once and passed on three
further runs, including one against the committed tree with every change
stashed. Not caused by this work, but worth knowing about.

`ProductCardRowView` could not be snapshotted: it renders three asynchronously
loaded images behind spinners, and three spinners land on a different frame of
the animation every run. The single-card case is stable, so the row is covered
by two card states instead. That is a fact about the view rather than about the
tool — a view whose appearance cannot be pinned cannot be regression-tested.
