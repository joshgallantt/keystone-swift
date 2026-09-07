# SwiftLint configs

Two configs that push a project toward the shape of the reference project,
[Real-Clean-Architecture-in-iOS-Example](https://github.com/joshgallantt/Real-Clean-Architecture-in-iOS-Example).

Every rule in both files was derived from that project by measurement, and
reports **zero violations on its 408 files**. So adopting either one whole does
not bury you: what it reports is the distance between your project and that one.

| File | What it adds | Use it |
| --- | --- | --- |
| `clean-architecture.yml` | Layering, naming, access control, tests | Start here |
| `clean-architecture-strict.yml` | The same, plus 54 style rules and 12 formatting defaults | When the structural work has landed |

Copy one to your repository root as `.swiftlint.yml`.

```bash
cp swiftlint/clean-architecture.yml /path/to/your-project/.swiftlint.yml
```

`clean-architecture-strict.yml` is generated from `clean-architecture.yml`. Edit
the first; do not edit the second by hand.

## Why two files

Measured on five sample apps:

| Project | Core | Strict |
| --- | --: | --: |
| Dimillian/MovieSwiftUI | 127 | 999 |
| Dimillian/IceCubesApp | 833 | 1,966 |
| basememara/SwiftUI-NewsReader | 312 | 357 |
| Jeon0976/iOS-CleanArchitecture-Sample | 289 | 387 |
| significa/ios-swiftui-tca-example | 43 | 72 |

The difference is almost entirely reformatting. `multiline_arguments_brackets`
alone is 619 findings on IceCubesApp, and `opening_brace` is 282 across four
apps. Those rules are real, and the reference does pass them, but a
whole-codebase reformat is the worst possible first commit for a rule set whose
subject is layering. Land the structure, then take the style.

## What these configs cannot do

SwiftLint custom rules are **regex over raw text**. They cannot read the module
graph, cannot follow a dependency, and will match `import UIKit` inside a
comment or a string literal.

So the layer rules here are a cheap first line that runs in Xcode as you type.
They catch `import CoreData` in a file under `Domain/`. They cannot catch:

- a domain type reaching a data type **inside one module**, where no import
  records the crossing
- a dependency cycle between modules
- a manifest that declares a dependency nothing imports
- a file whose layer nobody has decided

That is where `keystone-swift` starts. The two are complementary, and the
overlap is deliberate: the same fault caught earlier is worth catching twice.

## Two gotchas that cost an hour

**`included` and `excluded` inside a custom rule take regex. The top-level
`excluded` takes globs.** Mixing them up fails silently.

**`excluded` resolves relative to the config file.** Running
`swiftlint --config /elsewhere/clean-architecture.yml` from your project does
not exclude your `.build` directories — it excludes the ones next to the config.
On the reference project that mistake linted every checked-out dependency and
produced 346,243 violations. Copy the file into the repository instead.

## What was deliberately left out

- `object_literal` — demands exactly what `discouraged_object_literal` forbids.
  Both score zero on the reference only because it uses neither. Enable both and
  the first person to touch a colour literal is deadlocked.
- `explicit_acl` — 1,510 violations on the reference. `domain_top_level_acl`
  is the version worth having: the same idea, scoped to the layer whose surface
  other modules actually read.
- `sorted_imports` — 256. A convention the reference does not hold.
- Rules that would warn on `package` and on SE-0409 access-level imports. The
  reference happens not to use either, but both are the strongest enforcement
  Swift has, and a config that discourages them is working against its own
  purpose.

Six SwiftLint default rules are disabled because the reference violates them —
`vertical_whitespace` (13), `trailing_newline` (5), and four others in single
figures. They are listed with their counts in the file.
