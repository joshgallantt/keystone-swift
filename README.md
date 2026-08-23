# keystone-swift

**Architecture enforcement for iOS projects, in the write path.**

Point it at a Swift codebase. It reads the build graph, works out which layer every file belongs
to, and from then on refuses any change that crosses a boundary — before the write lands, with the
correction and the destination attached.

```
✗ dependency-rule  1 violation

  UI/BagUI/Sources/UI/BagScreen/BagViewModel.swift:4
    `presentation` imports `BagData`, which belongs to `data`

    A screen reaches the domain and never storage. Take the use case protocol through the
    initialiser and let the composition root decide which concrete type satisfies it — that
    is what makes the screen testable without a network or a database.

    Robert C. Martin, Clean Architecture (2017), Ch. 22 — The Clean Architecture.
```

No model decides anything. Same files plus same configuration gives the same answer, on your
machine and in CI, every time.

---

## The one idea

Every architecture checker identifies a layer by **naming** one — a roster of module names in a
manifest, a package string in an assertion. That is what ties them to one project.

keystone-swift identifies layers by **evidence**, and states every rule between *roles*:

```
domain       → nothing
data         → domain, library
presentation → domain, library
library      → library
composition  → anything
```

No project's names appear anywhere in that. An e-commerce app and a fitness tracker get the same
matrix. Two mechanisms make it work.

**The target graph.** Every `Package.swift` and `project.pbxproj` is parsed into targets, source
roots, dependencies and external packages. Each target gets a role. The dependency rule is then
checked twice — once against `import` statements, and once against the manifest edges, because an
import is a mistake while a manifest edge is a decision, and it is the decision that quietly makes
the next hundred mistakes legal.

**The symbol index.** Every type is indexed to the layer that declared it. This is what replaces
hardcoded rosters. Instead of *"a screen may not extend `Product`, `Bag` or `Order`"*, the rule is
*"a screen may not extend a domain type"* — and it works on a codebase nobody has read yet.

The index is also why **single-target apps are first-class**. With no modules there are no imports
to check, so boundaries are enforced by type reference instead: a file in `Presentation/` naming a
type declared in `Data/` has crossed the line whether or not the compiler noticed.

---

## Install

Needs Swift 6.0 or later, which you already have if you have Xcode.

```bash
git clone git@github.com:joshgallantt/keystone-swift.git ~/.keystone-swift
bash ~/.keystone-swift/install.sh
```

The first build compiles swift-syntax and takes about a minute. To remove it,
`bash ~/.keystone-swift/install.sh --uninstall`.

## Getting started

```bash
cd your-app

keystone-swift init             # read the project, write keystone-swift.json
keystone-swift check            # see where it stands today
keystone-swift baseline         # accept that as existing debt
keystone-swift install claude   # refuse violating writes from here on
keystone-swift install ci       # and hold the line in pull requests
```

`init` prints what it worked out before it writes anything:

```
MODULE            LAYER          FILES  WHY
Bag               domain         13     directory named `Domain`
BagData           data           4      directory named `Data`
BagDI             composition    1      directory named `DI`
BagUI             presentation   5      directory named `UI`
Networking        library        2      package under `Library`
iPhone            composition    13     application target

domain         90 files  Component/*/Sources/Domain/**
data           31 files  Component/*/Sources/Data/**
presentation   76 files  UI/*/Sources/UI/**
composition    35 files  */*/Sources/DI/**, iPhone/**
library         2 files  Library/**
tests          98 files  */*/Tests/**
```

**Read it before you trust it.** Inference runs exactly once, and its output is a file you review.
Everything afterwards is a pure function of that file — which is what makes two runs agree, and
what makes a wrong guess left in it a wrong rule rather than a mystery.

## Adopting this on an existing app

The point is not to inventory what is wrong. It is to move a codebase toward a shape it does not
have yet, one refusal at a time.

A first run on a real app reports hundreds of violations, which is indistinguishable from no signal
at all. So `keystone-swift baseline` records them as accepted debt and the tool goes quiet. From
that moment **nothing new gets in**, while the recorded number only ever falls:

```bash
keystone-swift status     # 63% of files are inside the architecture; 214 accepted, 0 new
keystone-swift baseline   # bank progress: 31 fixed since the last baseline
```

Every violation ends with a destination — `Move it to Component/Bag/Sources/Domain/` — computed
from your own layout rather than described in the abstract. That is what makes the backlog
something an agent can be pointed at and told to work through.

Delete the baseline when the project is clean, and the rules become absolute.

## Scope

A codebase being refactored needs more than "is the whole thing sound".

```bash
keystone-swift check                    the whole project
keystone-swift check --changed          what this branch changed, uncommitted work included
keystone-swift check --staged           what is staged for the next commit
keystone-swift check --branch feature/x what that branch changed against the trunk
keystone-swift check --commit a1b2c3d   what one commit touched
keystone-swift check --at v2.0.0        the project as it stood at a ref
```

*Which files* and *which tree* are separate questions, and conflating them is how a
tool ends up lying about history. `--commit` reads that commit's tree, not today's
working copy — reviewing last month's commit against today's files would report
violations in code it never contained. `--at` sets the tree independently when you want
the other combination.

## The rules

**Boundaries** — errors

| Rule | What it refuses |
| --- | --- |
| `dependency-rule` | A layer importing a layer it may not reach |
| `target-dependency-rule` | The same, declared in `Package.swift` or `project.pbxproj` |
| `framework-purity` | A layer importing a framework *category* it refuses — `ui`, `persistence`, `crypto` |
| `restricted-symbols` | `URLSession`, `FileManager` and friends arriving inside an allowed `Foundation` |
| `third-party-boundary` | A stable layer taking a dependency on somebody else's release schedule |
| `no-cycles` | Two modules that cannot be built, tested or deleted apart |
| `feature-isolation` | Sibling modules depending on each other, where a layer asks for that |
| `type-reference-boundary` | A boundary crossed inside one module, where no import can catch it |

**Structure** — errors

| Rule | What it refuses |
| --- | --- |
| `declaration-placement` | `*UseCase`, `*Repository`, `*DTO`, `*ViewModel`, `*View` in the wrong layer |
| `extension-boundary` | One layer reopening another layer's types |
| `no-extensions` | An extension that neither declares a conformance, extends a protocol, nor carries a constraint |

**Testing** — errors, except where noted

| Rule | What it checks |
| --- | --- |
| `test-tiers` | Every test file belongs to a declared tier |
| `support-separation` | `Support/` declares no tests |
| `tests-assert-something` | A file in a tier declares at least one |
| `doubles-live-in-support` | `Stub*`/`Spy*`/`Mock*`/`Fake*`/`Dummy*` outside `Support/` |
| `doubles-are-uniquely-named` | Two doubles sharing a name across the repository |
| `acceptance-vocabulary` | An acceptance test naming a type the data layer declared |
| `test-names-read-as-prose` | A business-facing test named as an identifier |
| `tier-required` | A package that owes a tier and has none |
| `test-pyramid` | A tier far narrower than the one above it *(warning)* |
| `no-shared-fixtures` | A file of shared test data *(warning)* |
| `snapshots-are-committed` | A snapshot suite with nothing recorded *(warning)* |

**Warnings**

| Rule | What it reports |
| --- | --- |
| `peer-consistency` | What most sibling packages have and one does not |
| `layer-vocabulary` | A domain protocol named for the wire — `*Client`, `*API`, `*Gateway` |
| `imports-are-declared` | A module imported but reached only transitively |
| `contract-before-implementation` | A `Default*` or `*Impl` that implements nothing |
| `no-shared-singletons` | A dependency reached for rather than passed in |
| `no-todo` | Work recorded where nobody will look for it |
| `unclassified-files` | A file no layer claims, and therefore no rule examined |

That last one matters more than it looks. Silence is every architecture checker's
failure mode: a file nothing claims passes everything, and a project can be entirely
"clean" while most of it is unexamined. During a migration it is also the progress bar.

### Conventions that are not defaults

`clients-live-in-data` and `stores-live-in-data` are deliberately absent. Both read well
until you meet the app they are wrong for — a CRM whose `Client` is its most important
entity, a retail app whose `Store` is a place on a map. `UseCase`, `Repository`, `DTO`,
`ViewModel` and `View` name *patterns*, so they ship as defaults; a suffix that is also
an ordinary noun cannot. Add them if they suit your domain:

```json
{ "name": "clients-live-in-data",
  "match": { "nameSuffix": "Client", "kinds": ["struct", "class", "actor"] },
  "requireRole": ["data"], "exemptRoles": ["tests", "composition", "library"] }
```

The same principle runs through the tool: `layer-vocabulary` flags a domain **protocol**
named `*Client`, because that is a service that borrowed a word from the layer below it,
and never a **struct** named `Client`, because that is somebody's whole business.

## Testing

Three tiers, because they answer different questions. An acceptance failure says *this
stopped working*; a unit failure says *which rule is wrong*; neither can tell you a
screen now lays something out wrongly.

```
<Package>/Tests/
  <Package>AcceptanceTests/
    BrowsingTests.swift              journeys — @Test("Someone who … ends up with …")
    Support/
      Store.swift                    the world: setting up what exists
      Shopper.swift                  the actor: the vocabulary the tests speak
      AThing.swift                   test data builders
  <Package>UnitTests/
    ThingTests.swift
    Support/
      Doubles.swift                  StubThing, SpyThing
  <Package>SnapshotTests/            packages with views
    ScreenSnapshots.swift
    __Snapshots__/                   committed
```

The `Support/` split is what makes everything else checkable. Without it a test target
is a bag of files and you cannot ask whether a suite asserts anything, or whether a
helper has grown assertions of its own.

Doubles carry their kind in the name, from Meszaros' *xUnit Test Patterns* by way of
Fowler's [Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html) —
a `Stub` answers, a `Spy` records, a `Mock` expects, a `Fake` works. The kind tells the
reader whether the test verifies state or behaviour.

**On Cucumber.** The discipline, not the tooling. Gherkin runners for Swift are dated or
unmaintained, and buy `.feature` files at the cost of an indirection between the sentence
and the code. `@Test("…")` gives the readable sentence natively, and unlike a runner,
keystone-swift can *enforce* the rest: prose names, and nothing from the data layer
named in the suite. A Gherkin runner would happily execute a feature file full of
`FakeCatalog`.

**On snapshots.** Apple ships none — not in Swift Testing, not in XCTest. The standard is
[pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing),
which has native Swift Testing support. `snapshots-are-committed` exists because a
snapshot suite whose references are not in the repository writes them on every run and
compares them against itself: green in CI, and never once able to fail.

A project with **no packages at all** is treated as a single one, so a one-target app is
held to its tiers rather than skipped — that being the codebase that needs them most.

`Tests/Fixtures/` holds two complete worked examples — a multi-package workspace and a
single-target app, deliberately about different things — and the suite holds both to
every rule.

## Agents

**Claude Code** — `keystone-swift install claude` (add `--user` for every project):

| Hook | What it does |
| --- | --- |
| `SessionStart` | Hands over the rules, generated from the manifest a moment before |
| `PreToolUse` | Refuses a `Write` or `Edit` that breaks a boundary; blocks shell redirection into `.swift` |
| `Stop` | Runs the whole-project pass before the turn is allowed to finish |

Reading a rule costs nothing; being refused costs a write and a retry. That is why the session hook
exists as well as the gate. The `Stop` hook is there because cycles, sibling coupling and
unclassified files cannot be seen from one write — without it they would first be noticed by CI,
after the work was handed over as finished.

Nothing is checked into your repository. A generated copy of the rules drifts from the manifest the
checker actually reads while still sounding authoritative, and an agent obeying a stale copy writes
code the hook then refuses.

**Kiro** — `keystone-swift install kiro`. Writes a hook and a steering file. Kiro's hooks fire
*after* a file is saved, so this reports rather than prevents; the steering file tells the agent to
read the rules first, which is the cheaper of the two.

**Anything else** — the tool is a normal command with defined exit codes:

```bash
cat pending.swift | keystone-swift check --file Sources/Domain/Order.swift
# 0 permitted   1 the write breaks a rule   2 could not decide
```

Exit `2` never blocks anything. An unreadable payload, a file no layer claims, a configuration that
will not load — all of them let the write through, because a tool that blocks on its own confusion
gets uninstalled by the end of the day, and CI still catches what the hook missed.

## CI

`keystone-swift install ci` writes `.github/workflows/architecture.yml`. It needs `fetch-depth: 0`
for the merge base, and a `KEYSTONE_SWIFT_TOKEN` secret while this repository is private.

It reports only what is new against the baseline, so it can be switched on today without failing
on inherited debt.

## Commands

| Command | |
| --- | --- |
| `init` | Read the project and write `keystone-swift.json` for review |
| `check` | Check the project. See [Scope](#scope) for `--changed`, `--commit`, `--at` |
| `status` | Which layers exist, what is unclassified, how much debt is left |
| `baseline` | Record today's violations as accepted |
| `rules` | Print the architecture as a document for an agent to read |
| `doctor` | What is installed, and whether the configuration loads |
| `install` / `uninstall` | `claude`, `kiro`, `ci`, or `all` |

## Configuration

```json
{
  "roles": {
    "domain": {
      "paths": ["Component/*/Sources/Domain/**"],
      "mayDependOn": [],
      "sameRole": "allow",
      "deniedFrameworks": ["ui", "persistence", "networking", "crypto"],
      "allowsThirdParty": false,
      "deniedSymbols": ["URLSession", "FileManager"],
      "reason": "Printed when this boundary is crossed. Write the correction, not the rule."
    }
  }
}
```

Roles are an open set — rename `domain` to `core`, or add a seventh layer, and the tool behaves
identically, because no rule reads a role's name. `mayDependOn: ["*"]` is what a composition root
is for. `sameRole` is `allow`, `denyAcrossPackages` or `deny`.

`reason` is not a comment. It is what gets printed, and what an agent is told to do instead.

## Limits

Manifests are parsed, not evaluated. A `Package.swift` that computes its target list yields nothing
rather than a guess — `swift package dump-package` would be exact but needs the network and takes
seconds, which is unusable in a hook that must answer before a write lands.

A type name declared in more than one module is skipped by the rules that read references, rather
than resolved to one of them and be right half the time.

Xcode's implicit target dependencies are not written down anywhere readable, so
`imports-are-declared` only applies to SwiftPM targets.

The Kiro integration reports after the write rather than refusing before it. That is Kiro's hook
model, not a limitation that will be fixed here.

## Sources

Rules cite the work they rest on, so you can go and disagree with the source rather than with the
tool.

- Robert C. Martin, *Clean Architecture* (2017)
- Martin Fowler, *Patterns of Enterprise Application Architecture* (2002)
- Mark Seemann & Steven van Deursen, *Dependency Injection: Principles, Practices, and Patterns* (2019)

The rule catalogue is adapted from a Konsist suite used in a production Android app, generalised so
that no rule names a module, and extended with the graph-level checks that suite could not express.
