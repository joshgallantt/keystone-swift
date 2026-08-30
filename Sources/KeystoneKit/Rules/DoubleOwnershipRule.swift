import Foundation

/// A test double belongs to the package that declares the protocol it stands
/// in for.
///
/// This is the rule that stops doubles multiplying. Without it, every package
/// that consumes a protocol writes its own stand-in for it, and a repository
/// ends up with four stubs for one collaborator — each drifting from the real
/// behaviour independently, each passing its own tests, and none of them wrong
/// in a way anybody can see. It is the argument in *Software Engineering at
/// Google*, Ch. 13, for the API's owner writing the fake rather than its
/// callers: one fake, in one place, that can be held against the real thing.
///
/// The Swift ecosystem does it structurally — `swift-nio` ships `NIOEmbedded`
/// beside the protocols it doubles, and `swift-dependencies` puts `testValue`
/// in the same declaration as the interface. Either way the double is part of
/// the interface's package, never the caller's.
///
/// Stated as ownership rather than as a naming convention, so it cannot be
/// satisfied by renaming: two stubs for one protocol in two packages remain two
/// stubs however they are spelled.
public struct DoubleOwnershipRule: Rule {
    public let identifier = "doubles-live-with-their-protocol"
    public let defaultSeverity: Severity = .warning
    public var needsWholeProject: Bool { true }

    public init() {}

    public func evaluate(_ context: RuleContext) -> [Violation] {
        let tests = context.configuration.tests
        guard !tests.isEmpty else { return [] }

        var violations: [Violation] = []

        for file in context.files {
            guard file.role?.isTestFacing == true,
                  let home = context.package(containing: file.path), !home.isEmpty else { continue }

            for declaration in file.facts.declarations
            where declaration.isTopLevel && declaration.isNominalType && tests.isDouble(declaration.name) {
                guard let (protocolName, owner) = DoubleOwnershipRule.owner(
                    of: declaration, in: context
                ), owner != home else { continue }

                // Unless moving it would turn the dependency around. A fake of
                // a library's protocol that is built out of one component's
                // types cannot go and live in the library: the library would
                // have to learn about the component, which is the boundary the
                // whole architecture exists to keep. Where the double cannot
                // follow its protocol, the protocol's owner is not its home,
                // and asking for the move would be asking for something worse
                // than the duplication it prevents.
                guard DoubleOwnershipRule.canFollow(from: home, to: owner, in: context) else { continue }

                violations.append(
                    Violation(
                        rule: identifier,
                        severity: defaultSeverity,
                        file: file.path,
                        line: declaration.line,
                        summary: "`\(declaration.name)` stands in for `\(protocolName)`, which "
                            + "`\(Paths.lastComponent(of: owner))` declares",
                        fix: "Move it to `\(Paths.join(owner, "Sources", "TestSupport"))/`, published as a "
                            + "product, and depend on that. "
                            + "A protocol's own package is the one place a stand-in for it "
                            + "can be kept honest, because that is where anyone changing the protocol will "
                            + "see it. Written here instead, this is one of however many copies the packages "
                            + "using `\(protocolName)` have each made — and copies of a double do not "
                            + "disagree loudly, they disagree by slowly describing different behaviour while "
                            + "every suite goes on passing.",
                        source: Sources.doubleOwnership
                    )
                )
            }
        }

        return violations
    }

    /// Whether the owning package is allowed to depend on the package the
    /// double lives in now — which is what moving it would require, since the
    /// double is built out of whatever is around it.
    static func canFollow(from home: String, to owner: String, in context: RuleContext) -> Bool {
        let roleOf: (String) -> Role? = { package in
            context.files.first {
                context.package(containing: $0.path) == package && $0.role?.isTestFacing == false
            }?.role
        }
        guard let here = roleOf(home), let there = roleOf(owner) else { return true }
        return context.permits(from: there, to: here, fromPackage: owner, toPackage: home) == .permitted
    }

    /// The protocol a double stands in for, and the package declaring it.
    ///
    /// A double usually adopts several things — `Sendable`, `@unchecked
    /// Sendable`, a marker or two — so the one that matters is the first
    /// conformance this project itself declares as a protocol. Anything the
    /// project did not declare is somebody else's, and not ours to place.
    static func owner(of declaration: Declaration, in context: RuleContext) -> (String, String)? {
        for name in declaration.inheritedTypes {
            let declarations = context.symbols.declarations(of: name)
            guard !declarations.isEmpty, declarations.allSatisfy({ $0.kind == .protocol }) else { continue }
            guard let site = declarations.first,
                  let owner = context.package(containing: site.file) else { continue }
            return (name, owner)
        }
        return nil
    }
}
