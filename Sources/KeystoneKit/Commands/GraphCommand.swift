import Foundation

/// The module graph as Mermaid, with the refused edges in red.
///
/// The tool already held the graph and the verdicts and printed neither. A list
/// of ninety-one violations tells you a rule is broken; a picture of the layers
/// with three red arrows across them tells you *what shape the project is*, and
/// that is the thing a team can stand in front of and argue about.
///
/// Mermaid rather than DOT because GitHub renders it in a README and in a pull
/// request without anyone installing Graphviz. Output goes to stdout and
/// nothing else does, so it pipes straight into a file or a clipboard.
///
/// The red edges come from `Configuration.permits`, which is the same predicate
/// `target-dependency-rule` uses. A picture that disagreed with the checker
/// would be worse than no picture at all.
extension Commands {
    static func graph(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }

        let result = Checker().checkProject(root: project.root, configuration: project.configuration)
        let graph = result.graph
        let assignment = result.assignment
        let configuration = project.configuration

        // Modules holding no Swift are left out. They cannot be judged against a
        // layer, so an edge to one of them would be a line whose colour means
        // nothing.
        var filesByModule: Set<String> = []
        for file in result.scannedFiles {
            if let module = graph.module(owning: file) { filesByModule.insert(module.name) }
        }
        let modules = graph.orderedModules.filter { filesByModule.contains($0.name) }
        guard !modules.isEmpty else {
            Output.error("No modules with Swift in them were found, so there is no graph to draw.")
            return ExitCode.undecidable
        }

        // Two narrower pictures, because the faithful one stops being useful at
        // scale. The reference project is 122 modules and 553 edges: every one
        // of them true, and nothing a person can read on a wall.
        //
        //   --roles    collapse to the layer graph — seven nodes, the picture
        //              you actually argue from
        //   --refused  only the refused edges and the modules they touch — the
        //              picture you work from
        let collapse = arguments.has("roles")
        let onlyRefused = arguments.has("refused")

        var identifiers: [String: String] = [:]
        for (index, module) in modules.enumerated() { identifiers[module.name] = "m\(index)" }

        // Grouped by layer, unplaced last, because the eye reads the top of the
        // picture first and an unplaced module is the least informative thing
        // in it.
        var byRole: [String: [Module]] = [:]
        for module in modules {
            byRole[assignment.role(ofModule: module.name)?.rawValue ?? "unplaced", default: []].append(module)
        }
        let order = configuration.orderedRoles.map(\.name.rawValue) + ["unplaced"]

        struct Edge {
            let from: Module
            let to: Module
            let verdict: DependencyVerdict
        }

        var edges: [Edge] = []
        for module in modules {
            for name in (graph.edges[module.name] ?? []).sorted() {
                guard let other = graph.modules[name], filesByModule.contains(name) else { continue }
                let verdict: DependencyVerdict
                if let from = assignment.role(ofModule: module.name),
                   let to = assignment.role(ofModule: name) {
                    verdict = configuration.permits(
                        from: from,
                        to: to,
                        fromPackage: module.packageDirectory,
                        toPackage: other.packageDirectory
                    )
                } else {
                    // One end has no layer, so nothing can be said about the
                    // edge. Drawn, and drawn neutral.
                    verdict = .permitted
                }
                edges.append(Edge(from: module, to: other, verdict: verdict))
            }
        }

        let refused = edges.filter { $0.verdict != .permitted }

        if collapse {
            Output.print(Commands.layerGraph(edges: edges.map { edge in
                (assignment.role(ofModule: edge.from.name)?.rawValue ?? "unplaced",
                 assignment.role(ofModule: edge.to.name)?.rawValue ?? "unplaced",
                 edge.verdict)
            }, order: order))
            return ExitCode.clean
        }

        var keep: Set<String> = []
        if onlyRefused {
            for edge in refused { keep.insert(edge.from.name); keep.insert(edge.to.name) }
            guard !keep.isEmpty else {
                Output.print("%% keystone-swift graph --refused")
                Output.print("%% no refused dependencies")
                return ExitCode.clean
            }
        }

        var out: [String] = []
        out.append("%% keystone-swift graph\(onlyRefused ? " --refused" : "")")
        out.append("%% \(modules.count) modules, \(edges.count) dependencies, \(refused.count) refused")
        out.append("graph LR")

        for role in order {
            let all = byRole[role] ?? []
            let members = onlyRefused ? all.filter { keep.contains($0.name) } : all
            guard !members.isEmpty else { continue }
            out.append("  subgraph \(sanitise(role))[\"\(role)\"]")
            for module in members.sorted(by: { $0.name < $1.name }) {
                out.append("    \(identifiers[module.name]!)[\"\(module.name)\"]")
            }
            out.append("  end")
        }

        let drawn = onlyRefused ? refused : edges
        for edge in drawn {
            let from = identifiers[edge.from.name]!
            let to = identifiers[edge.to.name]!
            if edge.verdict == .permitted {
                out.append("  \(from) --> \(to)")
            } else {
                out.append("  \(from) -- \"\(label(edge.verdict))\" --> \(to)")
            }
        }

        // `linkStyle` addresses an edge by its position in the order above, so
        // this has to be emitted after every edge and indexed the same way.
        for (index, edge) in drawn.enumerated() where edge.verdict != .permitted {
            out.append("  linkStyle \(index) stroke:#c0392b,stroke-width:2px,color:#c0392b")
        }

        let unplaced = (byRole["unplaced"] ?? []).filter { !onlyRefused || keep.contains($0.name) }
        if !unplaced.isEmpty {
            out.append("  classDef unplaced stroke-dasharray:4 3")
            let names = unplaced.map { identifiers[$0.name]! }.joined(separator: ",")
            out.append("  class \(names) unplaced")
        }

        Output.print(out.joined(separator: "\n"))
        return ExitCode.clean
    }

    /// What the red edge is refused *for*. Four words on an arrow is the whole
    /// reason to draw the picture rather than read the list.
    private static func label(_ verdict: DependencyVerdict) -> String {
        switch verdict {
        case .permitted: return ""
        case .roleRefused: return "not allowed"
        case .sameRoleRefused: return "siblings kept apart"
        case .notVisible: return "not visible"
        }
    }

    /// The same picture with every module of a layer merged into one node, and
    /// an edge kept once with the count of modules behind it. Seven nodes
    /// instead of a hundred and twenty-two.
    static func layerGraph(
        edges: [(from: String, to: String, verdict: DependencyVerdict)],
        order: [String]
    ) -> String {
        var counts: [String: (count: Int, verdict: DependencyVerdict)] = [:]
        for edge in edges where edge.from != edge.to || edge.verdict != .permitted {
            let key = "\(edge.from)\u{1}\(edge.to)"
            let existing = counts[key]
            counts[key] = (
                (existing?.count ?? 0) + 1,
                existing?.verdict == .permitted || existing == nil ? edge.verdict : existing!.verdict
            )
        }

        let present = order.filter { role in
            counts.keys.contains { $0.hasPrefix("\(role)\u{1}") || $0.hasSuffix("\u{1}\(role)") }
        }

        var out = ["%% keystone-swift graph --roles", "graph LR"]
        for role in present { out.append("  \(sanitise(role))[\"\(role)\"]") }

        let keys = counts.keys.sorted()
        for key in keys {
            let parts = key.split(separator: "\u{1}").map(String.init)
            let entry = counts[key]!
            let arrow = entry.verdict == .permitted
                ? "-- \"×\(entry.count)\" -->"
                : "-- \"×\(entry.count) \(label(entry.verdict))\" -->"
            out.append("  \(sanitise(parts[0])) \(arrow) \(sanitise(parts[1]))")
        }
        for (index, key) in keys.enumerated() where counts[key]!.verdict != .permitted {
            out.append("  linkStyle \(index) stroke:#c0392b,stroke-width:2px,color:#c0392b")
        }
        return out.joined(separator: "\n")
    }

    /// Mermaid identifiers take no hyphens, dots or spaces, and a module name
    /// takes all three.
    private static func sanitise(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "g" + String(cleaned)
    }
}
