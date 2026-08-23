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

## The rules

**Boundaries** — errors

| Rule | What it refuses |
| --- | --- |
| `dependency-rule` | A layer importing a layer it may not reach |
| `target-dependency-rule` | The same thing, declared in `Package.swift` or `project.pbxproj` |
| `framework-purity` | A layer importing a framework *category* it refuses — `ui`, `persistence`, `crypto` |
| `restricted-symbols` | `URLSession`, `FileManager` and friends arriving inside an allowed `Foundation` |
| `third-party-boundary` | A stable layer taking a dependency on somebody else's release schedule |
| `no-cycles` | Two modules that cannot be built, tested or deleted apart |
| `feature-isolation` | Sibling modules depending on each other, where a layer asks for that |
| `type-reference-boundary` | A boundary crossed inside one module, where no import can catch it |

**Placement** — errors

| Rule | What it refuses |
| --- | --- |
| `declaration-placement` | `*UseCase`, `*Repository`, `*DTO`, `*ViewModel`, `*View`, `*Client` in the wrong layer |
| `extension-boundary` | One layer reopening another layer's types |

**Warnings** — reported, never blocking

| Rule | What it reports |
| --- | --- |
| `imports-are-declared` | A module imported but reached only transitively |
| `contract-before-implementation` | A `Default*` or `*Impl` that implements nothing |
| `no-shared-singletons` | A dependency reached for rather than passed in |
| `no-todo` | Work recorded where nobody will look for it |
| `unclassified-files` | A file no layer claims, and therefore no rule examined |

That last one matters more than it looks. Silence is every architecture checker's failure mode: a
file nothing claims passes everything, and a project can be entirely "clean" while most of it is
unexamined. During a migration it is also the progress bar.

Change a severity or switch a rule off in `keystone-swift.json`:

```json
{
  "severities": { "no-todo": "error" },
  "disabledRules": ["imports-are-declared"]
}
```

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
| `check` | Check the project. `--changed` for this branch only, `--json` for machines |
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
