import Foundation

/// Narrow every layer's dependency allow-list to the edges that exist today.
///
/// The sibling of `baseline`, and a different instrument. `baseline` accepts
/// today's *violations* as debt, one entry per finding; on a large codebase
/// that is three thousand lines of accepted debt and a file nobody reads.
/// `freeze` moves up one level and accepts today's *shape*: each layer's
/// `mayDependOn` becomes the set of layers its modules actually reach. Nothing
/// that exists is reported any more, and any edge that did not exist this
/// morning is refused tomorrow.
///
/// It cuts both ways, and that is the point:
///
/// - Where a layer reaches **less** than the preset allows, the rule tightens.
///   A presentation layer that touches only the domain can no longer quietly
///   start using a library.
/// - Where a layer reaches **more** than the preset allows, the rule loosens,
///   and that is debt. Every widening is written into the manifest with a
///   `reason` saying so, and printed, because a rule that gets weaker in
///   silence is how a checker stops meaning anything.
///
/// A layer that may already depend on anything is left alone. Freezing
/// composition to the modules that exist today would refuse every new feature
/// on the day it is wired up, which is noise rather than architecture.
extension Commands {
    static func freeze(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let result = Checker().checkProject(root: project.root, configuration: project.configuration)
        let assignment = result.assignment
        let graph = result.graph
        let configuration = project.configuration

        // What each layer reaches today, at the level of layers. A module's own
        // layer is left out: whether siblings may see each other is
        // `sameRole`'s question, and freezing must not answer it by accident.
        //
        // Both kinds of evidence, because two rules read two different things.
        // `target-dependency-rule` reads the manifest edge;
        // `dependency-rule` reads the `import` in the file, and SwiftPM lets a
        // file import a module its target never declared. Freezing from the
        // manifest alone left every one of those imports still reported — the
        // command claimed to accept today's shape and silenced nothing.
        var observed: [String: Set<String>] = [:]
        var populated: Set<String> = []

        for module in graph.orderedModules {
            guard let from = assignment.role(ofModule: module.name) else { continue }
            populated.insert(from.rawValue)
            for name in graph.edges[module.name] ?? [] {
                guard let to = assignment.role(ofModule: name), to != from else { continue }
                observed[from.rawValue, default: []].insert(to.rawValue)
            }
        }

        let symbols = SymbolIndex.build(files: result.files, graph: graph)

        for file in result.files {
            guard let from = file.role ?? file.module.flatMap({ assignment.role(ofModule: $0.name) }),
                  !from.isTestFacing else { continue }
            populated.insert(from.rawValue)

            for reference in file.facts.imports {
                guard graph.modules[reference.module] != nil,
                      let to = assignment.role(ofModule: reference.module),
                      to != from else { continue }
                observed[from.rawValue, default: []].insert(to.rawValue)
            }

            // And the third kind of evidence, which is the only kind a monolith
            // has. Where every layer lives in one module there is no manifest
            // edge and no import to read — a screen names a domain type
            // directly, and `type-reference-boundary` is the rule that sees it.
            // Reading only imports froze a single-target app's layers to an
            // empty allow-list and then reported the type references it had
            // just made illegal, which is the opposite of what the command is
            // for.
            let declaredHere = Set(file.facts.declarations.map(\.name))
            for reference in file.facts.typeReferences {
                guard !declaredHere.contains(reference.name),
                      !symbols.isAmbiguous(reference.name),
                      let to = symbols.declaringRole(of: reference.name),
                      to != from else { continue }
                observed[from.rawValue, default: []].insert(to.rawValue)
            }
        }

        var tightened: [(role: String, removed: [String])] = []
        var loosened: [(role: String, added: [String])] = []
        var frozen: [String: [String]] = [:]

        for (role, definition) in configuration.roles.sorted(by: { $0.key < $1.key }) {
            if definition.dependsOnAnything { continue }
            if Role(role).isTestFacing { continue }
            // A layer with no modules in it has told us nothing. Freezing it to
            // an empty list would refuse the first module anyone adds, on the
            // strength of evidence that does not exist.
            guard populated.contains(role) else { continue }

            // A layer's own name stays if it was already there. Whether two
            // modules of one layer may see each other is `sameRole`'s question,
            // and freezing must not answer it by accident — the observed set
            // deliberately excludes same-layer edges, so reading it literally
            // stripped `library` from `library`.
            var now = observed[role] ?? []
            let before = Set(definition.mayDependOn)
            if before.contains(role) { now.insert(role) }
            guard now != before else { continue }

            frozen[role] = now.sorted()
            let removed = before.subtracting(now).sorted()
            let added = now.subtracting(before).sorted()
            if !removed.isEmpty { tightened.append((role, removed)) }
            if !added.isEmpty { loosened.append((role, added)) }
        }

        guard !frozen.isEmpty else {
            Output.print("Nothing to freeze. Every layer already reaches exactly what it is allowed to reach.")
            return ExitCode.clean
        }

        let path = Paths.join(project.root, ConfigurationLoader.fileName)

        if arguments.has("dry-run") {
            report(tightened: tightened, loosened: loosened, frozen: frozen, wrote: nil)
            return ExitCode.clean
        }

        do {
            try FreezeCommand.write(frozen: frozen, loosened: loosened, to: path)
        } catch {
            Output.error("Could not write \(path): \(error)")
            return ExitCode.undecidable
        }

        report(tightened: tightened, loosened: loosened, frozen: frozen, wrote: path)
        return ExitCode.clean
    }

    private static func report(
        tightened: [(role: String, removed: [String])],
        loosened: [(role: String, added: [String])],
        frozen: [String: [String]],
        wrote path: String?
    ) {
        if let path {
            Output.print("Froze \(frozen.count) layers into \(Paths.lastComponent(of: path)).")
        } else {
            Output.print("Would freeze \(frozen.count) layers.")
        }
        Output.print("")

        for entry in tightened {
            Output.print("  tightened  `\(entry.role)` no longer permits "
                + entry.removed.map { "`\($0)`" }.joined(separator: ", ")
                + " — nothing reaches it today")
        }
        for entry in loosened {
            Output.print("  WIDENED    `\(entry.role)` now permits "
                + entry.added.map { "`\($0)`" }.joined(separator: ", ")
                + " — this is debt, not a decision")
        }

        guard !loosened.isEmpty else { return }
        Output.print("")
        Output.print("The widened layers are recorded with a reason saying they were frozen rather than "
            + "chosen. They are the work: narrow each one by hand as you break the dependency, and the "
            + "list can only get shorter. Nothing stops you deleting a line from the manifest — the "
            + "checker will then say what it was hiding.")
    }
}

enum FreezeCommand {
    /// Writes only the keys that changed, over whatever manifest is already
    /// there.
    ///
    /// The loader deep-merges a manifest onto the preset, so a frozen project
    /// needs a handful of lines rather than a materialised copy of every
    /// default. Encoding the whole `Configuration` would have produced a
    /// six-hundred-line file in which the four lines that matter are invisible,
    /// and would have frozen every unrelated default at the same time.
    static func write(
        frozen: [String: [String]],
        loosened: [(role: String, added: [String])],
        to path: String
    ) throws {
        var top: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            top = existing
        }
        top["version"] = top["version"] ?? 1

        let widened = Dictionary(uniqueKeysWithValues: loosened.map { ($0.role, $0.added) })
        var roles = top["roles"] as? [String: Any] ?? [:]
        for (role, allowed) in frozen {
            var definition = roles[role] as? [String: Any] ?? [:]
            definition["mayDependOn"] = allowed
            if let added = widened[role] {
                definition["reason"] = "Frozen from the dependencies that existed when "
                    + "`keystone-swift freeze` ran. "
                    + added.map { "`\($0)`" }.joined(separator: ", ")
                    + " is permitted here because the code already does it, not because it should. "
                    + "Narrow this list as each one is broken."
            }
            roles[role] = definition
        }
        top["roles"] = roles

        let data = try JSONSerialization.data(
            withJSONObject: top,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: URL(fileURLWithPath: path))
    }
}
