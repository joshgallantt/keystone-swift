# keystone-swift

**keystone-swift checks the architecture of a Swift project.** It reads the
project and finds the layers in it. Then it checks each file against the rules
for its layer. It does this from the command line, in continuous integration
(CI), and before an AI agent writes a file.

The tool gives the same result for the same files. No model makes the decision.
If the tool cannot decide a rule, it does not apply the rule. It does not guess.

Each violation report shows you four things:

- the rule
- the location
- the correction
- the source of the rule

```
✗ dependency-rule  91 violations  ·  1 distinct

  `presentation` imports `MastodonCore`, which belongs to `data`  ×91
  Mastodon/Common/Views/BoostOrQuoteDialog.swift:6
  Mastodon/Common/Views/MetaTextInputField.swift:7
  … and 83 more files

    A screen reaches the domain and never storage. Take the use case protocol
    through the initialiser. Let the composition root decide which concrete type
    satisfies it.

    Robert C. Martin, Clean Architecture (2017), Ch. 22 — The Dependency Rule.
```

---

## Contents

[What the tool does](#what-the-tool-does) ·
[What the tool reads](#what-the-tool-reads) ·
[How the tool gives a layer to each file](#how-the-tool-gives-a-layer-to-each-file) ·
[What the tool detects](#what-the-tool-detects) ·
[Installation](#installation) ·
[Commands](#commands) ·
[How to start on an old project](#how-to-start-on-an-old-project) ·
[The configuration file](#the-configuration-file) ·
[Agents](#agents) ·
[Continuous integration](#continuous-integration) ·
[Limits](#limits) ·
[Sources](#sources)

---

## What the tool does

A Swift compiler stops a module when that module uses a symbol that it cannot
see. This is a strong control. But the compiler cannot see the difference
between a screen and a business rule. Two types in one module are equal to the
compiler.

keystone-swift adds that difference. It puts each file into a layer. Then it
applies the rules for that layer.

There are seven layers:

| Layer | What it holds |
| --- | --- |
| `domain` | Entities, use cases, and the contracts for them. The stable centre. |
| `data` | Repositories, clients, stores, and data transfer objects (DTOs). |
| `presentation` | Views and view models. |
| `composition` | The one place that knows every concrete type. Wiring only. |
| `library` | Utilities with no knowledge of the application. |
| `testSupport` | Doubles, drivers, and builders that test targets share. |
| `tests` | Test targets. |

The tool does not tell you to use these seven layers. It finds the layers that
your project already has.

---

## What the tool reads

The tool reads the structure of the project. It does not need a configuration
file.

It reads these sources:

- **Swift package manifests.** The tool reads each `Package.swift` file. It
  finds every target and every product in the file. A manifest can calculate its
  target list. The tool reads those targets also.
- **Xcode projects.** The tool reads each `project.pbxproj` file. It finds the
  targets and their kinds.
- **Directory names.** A directory with the name `Domain`, `Data`, `UI` or
  `Tests` tells the tool what is in it.
- **The module graph.** The tool reads which module depends on which module.
- **The Swift source.** A parser reads each file. The tool does not use regular
  expressions. A type name in a comment or in a string is not a declaration.

---

## How the tool gives a layer to each file

This is the most important part of the tool. Every rule is only as correct as
the layer that the tool gives to a file.

The tool applies five tests, in this sequence. The first test that gives an
answer is the answer.

1. **A path that the project declares.** The configuration file can name a path
   for a layer. This wins against all other evidence.
2. **A directory that states its layer.** A directory with the name `Domain`
   or `UI` shows a decision that somebody made. The tool reads the directory names
   from the file outward. The nearest directory wins.
3. **The kind of the target.** A manifest that declares a `.testTarget` states a
   fact. An Xcode target of the kind "application" states a fact. A fact is
   stronger than a name.
4. **The end of a directory name.** A module with the name `AuthUIDI` carries
   its layer in its own name. The tool reads this from the nearest directory
   only. It does not read the name of a parent directory.
5. **The shape of the dependencies.** A module that depends on a domain module
   and on a data module connects them. Thus it is composition.

The sequence is important. Before, the tool applied test 4 to every directory in a
path. A project below a directory with the name `ModularSwiftUI` became
presentation, from the top of the tree to the bottom. The same files below a
directory with the name `AppCore` became domain. The tool now reads a name
suffix from the nearest directory only.

The tool records which files got a layer from test 3 alone. Such a file tells
you nothing about itself. `type-reference-boundary` does not speak about these
files, because a boundary between a layer and a default is not a boundary.

If no test gives an answer, the file has no layer. The tool reports this with
`unclassified-files`. It does not guess.

---

## What the tool detects

There are 23 rules. This table groups them by what they examine.

### Boundaries between layers

| Rule | What it detects |
| --- | --- |
| `dependency-rule` | An `import` of a module that the layer must not use |
| `target-dependency-rule` | The same, as the build system declares it |
| `not-visible` | A module that reaches a module which is visible to other layers only |
| `feature-isolation` | One feature that imports another feature |
| `type-reference-boundary` | The same fault inside one module, where no import shows it |
| `extension-boundary` | One layer that reopens a type of another layer |
| `no-cycles` | A loop in the module graph |

### What a layer may touch

| Rule | What it detects |
| --- | --- |
| `framework-purity` | A platform framework in a layer that must not know it |
| `restricted-symbols` | `URLSession`, `FileManager` or `UserDefaults`, which arrive inside Foundation |
| `third-party-boundary` | A dependency on another person's package, in a layer that must outlive it |

### Where a declaration lives

| Rule | What it detects |
| --- | --- |
| `declaration-placement` | A type in the wrong layer for what it is |
| `contract-before-implementation` | A type that is named as an implementation, but implements nothing |
| `layer-vocabulary` | A layer that uses the words of a different layer |
| `imports-are-declared` | An `import` that the manifest does not declare |
| `no-shared-singletons` | A global instance, which is a dependency that nobody declared |

### Tests

| Rule | What it detects |
| --- | --- |
| `support-separation` | A test in a `Support/` directory, or a support file with tests in it |
| `tests-assert-something` | A test suite that asserts nothing |
| `acceptance-vocabulary` | A business-facing test that names a concrete type |
| `test-names-read-as-prose` | A business-facing test with a name that a person cannot read |
| `snapshots-are-committed` | A snapshot suite with no recorded snapshots |
| `doubles-are-uniquely-named` | Two test doubles with the same name |
| `doubles-live-with-their-protocol` | A double in a different package from its protocol |

### Coverage

| Rule | What it detects |
| --- | --- |
| `unclassified-files` | A Swift file that no layer claims, thus no rule examined |

### What the tool does not detect

The tool reads structure. It does not read behaviour. It does not compile your
code. A project can be correct for all 23 rules and not build. Use the tool with
your build, not in place of it.

The tool does not report a style. It had rules for extensions, for test
directory names, and for `TODO` comments. Those rules made 59% of all of the
output on a sample of 32 open-source applications. They reported the name of a
file. They did not report a dependency, a boundary, or a layer. The tool no
longer has them.

---

## Installation

You need **Swift 6.2** or a later version, and **git**.

```bash
git clone git@github.com:joshgallantt/keystone-swift.git
cd keystone-swift
./install.sh
```

Then go to your project and run the tool:

```bash
cd your-project
keystone-swift
```

The tool needs no configuration file. It reads your project.

---

## Commands

| Command | What it does |
| --- | --- |
| `keystone-swift` | Check the project. This is the default command. |
| `keystone-swift status` | Show the layers, the unclassified files, and the debt |
| `keystone-swift baseline` | Record today's violations as accepted debt |
| `keystone-swift rules` | Print the architecture as a document |
| `keystone-swift rules --list` | Show each rule and its severity |
| `keystone-swift init` | Write `keystone-swift.json` for you to examine |
| `keystone-swift doctor` | Show what is installed, and if the configuration loads |
| `keystone-swift install claude` | Add the agent hook |

### What to check

| Option | What the tool checks |
| --- | --- |
| (none) | The whole project |
| `--changed` | What this branch changed, with the uncommitted work |
| `--staged` | What is staged for the next commit |
| `--branch <name>` | What a branch changed against the trunk |
| `--commit <sha>` | What one commit touched |
| `--at <ref>` | The project as it was at a reference |
| `--file <path>` | One file. Send the content on stdin. |

### Output options

| Option | What it does |
| --- | --- |
| `--json` | Machine-readable output |
| `--reporter xcode` | One line for each violation, which Xcode shows inline |
| `--reporter github` | Annotations for GitHub Actions |
| `--include-accepted` | Report the violations that the baseline accepted also |
| `--no-colour` | Plain text |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Clean |
| `1` | The tool found violations |
| `2` | The tool could not decide |

Code `2` never stops your work. A tool that fails closed on its own confusion is
a tool that you remove.

---

## How to start on an old project

An old project has violations. Do not try to correct all of them.

1. Run `keystone-swift status`. Read how much of the project has a layer.
2. Correct the unclassified files first. A file with no layer gets no
   examination. Move it, or exclude it on purpose.
3. Run `keystone-swift baseline`. This records today's violations as accepted
   debt.
4. Run `keystone-swift --changed` in your work. Only new violations fail.
5. Correct the accepted violations when you touch the code near them.

The recorded number goes down. It does not go up.

---

## The configuration file

Most projects need no configuration file. The tool reads the layout from the
repository.

A manifest holds two things:

- an exemption, with the reason for it
- a path or a target name, for a layout that the tool cannot read

Do not add an option to stop a false report. If a rule needs an option to be
correct, the rule is wrong. Tell us about it.

```json
{
  "version": 1,
  "name": "MyApp",
  "roles": {
    "domain": { "targets": ["MyAppCore", "MyAppKit"] }
  }
}
```

---

## Agents

An AI agent writes files quickly. A rule that CI applies one hour later is a
rule that the agent has already broken many times.

```bash
keystone-swift install claude
```

This does two things:

- The agent reads your architecture at the start of each session.
- The tool examines each write **before** it lands.

The hook answers with one of three codes:

| Code | Meaning |
| --- | --- |
| `0` | The write is permitted |
| `1` | The write breaks a rule |
| `2` | The tool could not decide |

The reason that the tool gives is the correction. The agent then writes the file
in the correct place.

---

## Continuous integration

```bash
keystone-swift install ci
```

This writes a GitHub Actions workflow. The workflow checks the changes in a pull
request. It writes an annotation on each line that breaks a rule.

---

## Limits

The tool has these limits today. `TODO.md` records each one.

- **XcodeGen projects.** The tool cannot read a `project.yml` file. A project
  that generates its Xcode project, and does not commit it, has no modules that
  the tool can find.
- **Tuist projects.** The tool cannot read `Project.swift` or `Workspace.swift`.
- **Objective-C files.** The tool reads Swift only. It does not count a `.m` or
  a `.h` file. Thus `status` can tell you that 100% of the Swift files have a
  layer, in a project that is half Objective-C.
- **Behaviour.** The tool reads structure. See
  [What the tool does not detect](#what-the-tool-does-not-detect).

---

## Sources

Each rule names the work that it comes from. The tool does not invent
architecture. These are the sources:

- Robert C. Martin, *Clean Architecture* (2017)
- Eric Evans, *Domain-Driven Design* (2003)
- Martin Fowler, *Patterns of Enterprise Application Architecture* (2002)
- Steve Freeman and Nat Pryce, *Growing Object-Oriented Software, Guided by
  Tests* (2009)
- Gerard Meszaros, *xUnit Test Patterns* (2007)
- Mark Seemann and Steven van Deursen, *Dependency Injection* (2019)
- Bertrand Meyer, *Object-Oriented Software Construction* (1997)

Run `keystone-swift rules` to read your architecture, with each source.
