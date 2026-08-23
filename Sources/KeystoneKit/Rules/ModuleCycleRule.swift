import Foundation

/// No loops in the module graph.
///
/// A cycle means neither module can be built, tested, understood or deleted on
/// its own — they are one module wearing two names. Cycles are also the failure
/// that no per-file check can catch, which is why this rule waits for the whole
/// project and why the agent integration runs a full pass before it lets a
/// session finish.
public struct ModuleCycleRule: Rule {
    public let identifier = "no-cycles"
    public let defaultSeverity: Severity = .error
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let components = ModuleCycleRule.stronglyConnectedComponents(context.graph.edges)
        var violations: [Violation] = []

        for component in components {
            guard component.count > 1 || ModuleCycleRule.isSelfLoop(component, in: context.graph.edges) else { continue }
            guard let entry = component.sorted().first,
                  let module = context.graph.modules[entry] else { continue }

            let path = ModuleCycleRule.shortestCycle(from: entry, within: Set(component), edges: context.graph.edges)
            let rendered = path.joined(separator: " → ")

            violations.append(
                Violation(
                    rule: identifier,
                    severity: defaultSeverity,
                    file: module.manifestPath,
                    line: module.manifestLine,
                    summary: "`\(entry)` is in a dependency cycle: \(rendered)",
                    fix: "Break the loop at its weakest edge. The usual cause is one module reaching back for a "
                        + "type the other owns: move that type down into a module they both already depend on, or "
                        + "invert the edge by declaring a protocol on the side that is called and conforming to it "
                        + "on the side that calls. Until the loop is gone, neither of these modules can be built, "
                        + "tested or replaced without the other.",
                    source: Sources.acyclicDependencies
                )
            )
        }

        return violations
    }

    static func isSelfLoop(_ component: [String], in edges: [String: Set<String>]) -> Bool {
        guard let only = component.first, component.count == 1 else { return false }
        return edges[only]?.contains(only) ?? false
    }

    /// Tarjan's algorithm, iterative so that a pathological graph cannot
    /// overflow the stack of a tool that runs inside someone's editor.
    static func stronglyConnectedComponents(_ edges: [String: Set<String>]) -> [[String]] {
        var index = 0
        var indices: [String: Int] = [:]
        var lowLinks: [String: Int] = [:]
        var onStack: Set<String> = []
        var stack: [String] = []
        var result: [[String]] = []

        let nodes = edges.keys.sorted()

        for start in nodes where indices[start] == nil {
            var work: [(node: String, neighbours: [String], position: Int)] = [
                (start, (edges[start] ?? []).sorted(), 0)
            ]
            indices[start] = index
            lowLinks[start] = index
            index += 1
            stack.append(start)
            onStack.insert(start)

            while var frame = work.popLast() {
                if frame.position < frame.neighbours.count {
                    let neighbour = frame.neighbours[frame.position]
                    frame.position += 1
                    work.append(frame)

                    if indices[neighbour] == nil {
                        indices[neighbour] = index
                        lowLinks[neighbour] = index
                        index += 1
                        stack.append(neighbour)
                        onStack.insert(neighbour)
                        work.append((neighbour, (edges[neighbour] ?? []).sorted(), 0))
                    } else if onStack.contains(neighbour) {
                        lowLinks[frame.node] = min(lowLinks[frame.node]!, indices[neighbour]!)
                    }
                    continue
                }

                if lowLinks[frame.node] == indices[frame.node] {
                    var component: [String] = []
                    while let top = stack.popLast() {
                        onStack.remove(top)
                        component.append(top)
                        if top == frame.node { break }
                    }
                    result.append(component.sorted())
                }

                if let parent = work.popLast() {
                    lowLinks[parent.node] = min(lowLinks[parent.node]!, lowLinks[frame.node]!)
                    work.append(parent)
                }
            }
        }

        return result.sorted { ($0.first ?? "") < ($1.first ?? "") }
    }

    /// A concrete loop through the component, so the message shows the path
    /// rather than an unordered set of names.
    static func shortestCycle(from start: String, within component: Set<String>, edges: [String: Set<String>]) -> [String] {
        var queue: [[String]] = [[start]]
        var visited: Set<String> = []

        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard let last = path.last else { continue }
            for neighbour in (edges[last] ?? []).sorted() where component.contains(neighbour) {
                if neighbour == start { return path + [start] }
                if visited.contains(neighbour) { continue }
                visited.insert(neighbour)
                queue.append(path + [neighbour])
            }
        }

        return component.sorted() + [start]
    }
}
