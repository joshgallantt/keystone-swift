import Foundation

/// A type named as an implementation should be implementing something.
///
/// `DefaultOrderRepository` and `OrderRepositoryImpl` are both saying out loud
/// that a contract exists somewhere. When no protocol is behind the name, the
/// name is aspirational: callers are bound to the concrete type, nothing can be
/// substituted in a test, and the layer above has no seam to be injected
/// through. A warning, because the code works — it is the next change that
/// will be expensive.
public struct ContractBeforeImplementationRule: Rule {
    public let identifier = "contract-before-implementation"
    public let defaultSeverity: Severity = .warning

    /// The two ways Swift codebases say "this is the real one".
    static let prefixes = ["Default"]
    static let suffixes = ["Impl", "Implementation"]

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        var violations: [Violation] = []

        for file in context.files {
            guard let role = file.role, role != .tests else { continue }

            // A conformance added in an extension counts. Swift lets a type
            // adopt a protocol anywhere in the file, and a rule that only read
            // the declaration line would be wrong about a common style.
            let conformedInExtension = Set(
                file.facts.extensions.filter { !$0.inheritedTypes.isEmpty }.map(\.name)
            )

            for declaration in file.facts.declarations
            where declaration.isTopLevel
                && [.struct, .class, .actor].contains(declaration.kind)
                && ContractBeforeImplementationRule.readsAsImplementation(declaration.name)
                && declaration.inheritedTypes.isEmpty
                && !conformedInExtension.contains(declaration.name) {

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(declaration.name)` is named as an implementation but conforms to nothing",
                        fix: "Either declare the protocol this type is the default implementation of and conform "
                            + "to it, or rename the type to say what it is. Without the protocol there is no seam: "
                            + "callers bind to `\(declaration.name)` itself, a test cannot substitute anything for "
                            + "it, and the layer that depends on it cannot be built without it.",
                        source: Sources.separatedInterface
                    )
                )
            }
        }

        return violations
    }

    static func readsAsImplementation(_ name: String) -> Bool {
        prefixes.contains { name.hasPrefix($0) && name.count > $0.count }
            || suffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }
}
