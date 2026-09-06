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

- **Two placement implementations, and they now disagree.** `RoleAssignment`
  places files and modules for `check`, and reads file contents to do it.
  `RoleInference` does the same job for `init` and never parses anything, so
  `init --dry-run` reports "nothing placed it" for modules that `check` places
  confidently from their conformances. One of them has to go, and it is
  `RoleInference` — `Commands.initialise` should build a `RoleAssignment` the
  way `Checker` does.
- **A mixed file is reported as nothing rather than as a mixture.**
  `ContentMarkers.layers(in:)` returns every layer whose machinery a file is
  built on, and `role(of:)` uses it only to abstain when there is more than one.
  A file holding a screen and a store is a layering fault inside one file, and
  the set is already computed — it wants a rule.
- **`sources:` subpaths are not source roots.** A SwiftPM target written as
  `path: "Sources", sources: ["AuthUIHost", "AuthUIDI"]` reports one root,
  `Sources`, so the three `*DI` modules in the reference project read as
  presentation from the `UI` above them while nineteen siblings read as
  composition.

- **XcodeGen projects are unreadable.** `bitwarden/ios` — 2,761 Swift files —
  defines itself in `project-bwa.yml`, `project-pm.yml` and `project-common.yml`
  and commits no `.xcodeproj`, so the tool finds no modules and classifies 64%
  of the tree. XcodeGen's spec is a YAML map of `targets:` with `sources:`,
  `dependencies:` and `type:`, which is a literal read with no inference in it.
  Held back deliberately: the SwiftPM reader was the larger win and shipped
  first.
- **Tuist projects are unreadable.** `JonatanOrtiz/Similarity` classifies 31%.
  `Project.swift` and `Workspace.swift` are Swift programs declaring
  `Target(name:sources:dependencies:)`, so the same tree-walk that now reads a
  computed `Package.swift` would read them — but Tuist's manifests import a
  `ProjectDescription` module with its own vocabulary, and the graph lives
  across `Workspace.swift` plus one `Project.swift` per module. Worth doing
  after XcodeGen, which is the simpler shape.
- **`.m` and `.h` files are invisible.** `ProjectScanner` keeps only `*.swift`,
  and `UnclassifiedFileRule` iterates the files that survived that filter, so an
  Objective-C file is not merely unchecked — it is not even reported as
  unclassified. `StatusCommand` then divides classified by classified-plus-
  unclassified over Swift alone, so a codebase that is 60% Objective-C is told
  "100% of Swift files are inside the architecture", which is the exact silence
  `UnclassifiedFileRule` exists to prevent. 216 such files sit in the 32-app
  sample.

- ~~**`testSupport` role.**~~ Done, along with `visibleTo` — the inverse of
  `mayDependOn`, needed because the layer most in need of stopping is the
  composition root, which may depend on everything by definition.
- ~~**Per-rule options.**~~ Settled in the negative. `peer-consistency` carried
  four of them — `minimumPeers`, `threshold`, `ignore`, `exempt` — and all four
  existed to tune an argument from what sibling packages happen to have. The
  rule is gone and the `consistency` section with it. A knob is a failure to
  infer: where a rule needs one to avoid a false positive, the rule is wrong,
  and the answer is fewer rules that need parameters rather than a general shape
  for parameters. `test-pyramid` and its ratio are gone with the rest.

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

Measured, not assumed: of 256 SwiftLint rules and the rules here, there is now
no overlap at all. The one shared rule was `todo`/`no-todo`, and
`no_grouping_extension` partially subsumed `no-extensions`; both of ours are
deleted, so the question of delegating to SwiftLint has answered itself.

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
