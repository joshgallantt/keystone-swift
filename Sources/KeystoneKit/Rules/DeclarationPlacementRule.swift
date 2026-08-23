import Foundation

/// A naming convention, enforced as a location.
///
/// `*Repository` as a protocol is a contract and belongs to the domain; the
/// same suffix on a struct is an implementation and belongs to data. Stating
/// both turns a convention that a reviewer might mention into one the codebase
/// cannot drift away from — and, over time, into a layout that matches the
/// architecture whether or not anyone set out to build it that way.
public struct DeclarationPlacementRule: Rule {
    public let identifier = "declaration-placement"
    public let defaultSeverity: Severity = .error

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let advisor = DestinationAdvisor(configuration: context.configuration)
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, !role.isTestFacing else { continue }

            for convention in context.configuration.conventions {
                guard !convention.exemptRoles.contains(role),
                      !convention.requireRole.isEmpty,
                      !convention.requireRole.contains(role) else { continue }

                for declaration in file.facts.declarations where declaration.isTopLevel {
                    guard DeclarationPlacementRule.matches(declaration, convention.match) else { continue }

                    let destination = convention.requireRole
                        .compactMap { advisor.directory(for: $0, movingFrom: file.path) }
                        .first

                    violations.append(
                        Violation(
                            rule: identifier,
                            severity: convention.severity ?? defaultSeverity,
                            file: file.path,
                            line: declaration.line,
                            summary: "`\(declaration.name)` is in `\(role)`, and \(convention.name) puts it in "
                                + DeclarationPlacementRule.list(convention.requireRole),
                            fix: DeclarationPlacementRule.advice(
                                convention: convention,
                                declaration: declaration,
                                destination: destination
                            ),
                            source: convention.source
                        )
                    )
                }
            }
        }

        return violations
    }

    static func matches(_ declaration: Declaration, _ match: ConventionMatch) -> Bool {
        let hasCriterion = match.nameSuffix != nil || match.namePrefix != nil
            || match.nameMatches != nil || match.kinds != nil
        guard hasCriterion else { return false }

        if let kinds = match.kinds, !kinds.contains(declaration.kind) { return false }
        // The name must be longer than the affix. A type called exactly `View`,
        // `Client` or `Store` is a domain noun in somebody's app, not an
        // instance of the pattern this convention is about.
        if let suffix = match.nameSuffix {
            guard declaration.name.hasSuffix(suffix), declaration.name.count > suffix.count else { return false }
        }
        if let prefix = match.namePrefix {
            guard declaration.name.hasPrefix(prefix), declaration.name.count > prefix.count else { return false }
        }
        if let pattern = match.nameMatches {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(declaration.name.startIndex..<declaration.name.endIndex, in: declaration.name)
            if regex.firstMatch(in: declaration.name, options: [], range: range) == nil { return false }
        }
        return true
    }

    static func advice(convention: Convention, declaration: Declaration, destination: String?) -> String {
        var parts: [String] = []
        if let reason = convention.reason { parts.append(reason) }
        if let destination {
            parts.append("Move `\(declaration.name)` to \(destination).")
        }
        if parts.isEmpty {
            parts.append(
                "Move `\(declaration.name)` into "
                + DeclarationPlacementRule.list(convention.requireRole) + "."
            )
        }
        return parts.joined(separator: " ")
    }

    static func list(_ roles: [Role]) -> String {
        let names = roles.map { "`\($0)`" }
        switch names.count {
        case 0: return "no layer"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " or " + names.last!
        }
    }
}
