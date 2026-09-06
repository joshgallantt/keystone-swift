import Foundation

/// The sentences boundary rules share.
///
/// Wording is part of the product here. Every message has to work for a reader
/// who has not read the architecture yet — an agent starting a fresh session,
/// or someone three weeks into a codebase — so each one names the layer, what
/// it may reach instead, and where the code should go. A message that only says
/// "not allowed" gets worked around; one that says where to put it gets obeyed.
public enum BoundaryPhrasing {
    /// What a layer is permitted to reach, as prose.
    public static func permittedTargets(_ definition: RoleDefinition) -> String {
        if definition.dependsOnAnything { return "anything" }
        let allowed = definition.mayDependOn.sorted()
        switch allowed.count {
        case 0: return "nothing"
        case 1: return "`\(allowed[0])`"
        case 2: return "`\(allowed[0])` and `\(allowed[1])`"
        default:
            let head = allowed.dropLast().map { "`\($0)`" }.joined(separator: ", ")
            return "\(head) and `\(allowed.last!)`"
        }
    }

    /// The instruction given when a layer reached past what it is allowed.
    ///
    /// The layer's `reason` used to be returned on its own, and every layer in
    /// the preset has one, so the three sentences below — which name the other
    /// layer, what to depend on instead, and the directory the implementation
    /// belongs in — were never reached. The reason is the principle; these are
    /// the instructions for this file. Both, in that order.
    public static func invert(
        role: Role,
        definition: RoleDefinition,
        towards other: Role,
        file: String,
        advisor: DestinationAdvisor
    ) -> String {
        var lines = [
            "`\(role)` may depend on \(permittedTargets(definition)), and `\(other)` is not among them."
        ]

        if definition.mayDependOn.isEmpty {
            lines.append(
                "Declare what you need as a protocol here, in `\(role)`, and let a layer that may see "
                + "both supply the implementation. The dependency then points inward, which is the whole rule."
            )
        } else {
            lines.append(
                "Depend on a protocol declared in \(permittedTargets(definition)) instead, and let the "
                + "composition root decide which concrete type satisfies it."
            )
        }

        if let destination = advisor.directory(for: other, movingFrom: file) {
            lines.append("The implementation belongs in \(destination), reached only through that protocol.")
        }

        var text = lines.joined(separator: " ")
        if let reason = definition.reason { text += "\n\n" + reason }
        return text
    }

    /// Who a layer lets in, as prose.
    public static func audience(_ definition: RoleDefinition?) -> String {
        let roles = (definition?.visibleTo ?? []).sorted().map { "`\($0)`" }
        switch roles.count {
        case 0: return "nobody"
        case 1: return roles[0]
        default: return roles.dropLast().joined(separator: ", ") + " and " + roles.last!
        }
    }

    /// Said when a layer refuses to be depended on, rather than the other way
    /// round. The distinction matters: nothing is wrong with what this layer
    /// reached for, only with its being the one reaching.
    public static func refusedVisibility(to other: Role, from role: Role, context: RuleContext) -> String {
        let definition = context.configuration.definition(for: other)
        return "`\(other)` is visible to \(audience(definition)), and `\(role)` is not among them. "
            + "This is not about what `\(role)` may reach — it is that `\(other)` exists for a narrower "
            + "audience, and widening it would put that code somewhere it was never meant to ship."
    }

    public static func packageOf(_ module: Module?) -> String? {
        module?.packageDirectory
    }
}
