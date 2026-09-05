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
- ~~**Per-rule options.**~~ Settled in the negative. `peer-consistency` carried
  four of them — `minimumPeers`, `threshold`, `ignore`, `exempt` — and all four
  existed to tune an argument from what sibling packages happen to have. The
  rule is gone and the `consistency` section with it. A knob is a failure to
  infer: where a rule needs one to avoid a false positive, the rule is wrong,
  and the answer is fewer rules that need parameters rather than a general shape
  for parameters. `test-pyramid`'s ratio stays in `tests` because a pyramid is a
  ratio and there is nothing to infer it from.

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

**Clean, and green.** `✓ 348 files, no violations`, from twenty-six errors and
fifty-nine warnings; all 48 test schemes pass. Every UI package has a snapshot
suite with its references committed, and doubles two suites share live in the
package that owns the protocol they stand in for.

Its `keystone-swift.json` holds three exemptions and the reasons for them —
Product fetches its catalogue rather than storing it, SearchHistory never
crosses a wire, Session groups its stores because it has eight data files where
its neighbours have two to four. That is a decision record, which is what a
manifest is for; the layout is still read from the repository.

`ProductCardRowView` could not be snapshotted: three asynchronously loaded
images behind spinners land on a different frame every run. The single-card case
is stable, so the row is covered by two card states instead — a fact about the
view, not the tool.

## What the tool cannot see

`keystone-swift check` reported zero violations against a project that did not
compile. It reads structure — layers, dependencies, placement — and knows
nothing about types. Every file was in the right layer and every dependency
declared while a double had lost a member its callers still used.

A `--build` mode that shells out to `xcodebuild` and reports failures in the
same format has an obvious appeal and is probably wrong: it would make the tool
own a toolchain, a destination and a scheme list, and it would be slower than
the build it wraps. The honest fix is documentation — the check is not a
substitute for building — and possibly a `doctor` line saying so.
