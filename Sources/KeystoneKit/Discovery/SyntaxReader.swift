import Foundation
import SwiftSyntax

/// The few things this tool needs to read out of Swift source, expressed once.
///
/// Manifests are parsed rather than evaluated. `swift package dump-package`
/// would be exact, but it builds the manifest, which needs the network and
/// takes seconds — unusable in a hook that must answer before an agent's write
/// lands. Parsing reads the declarative form every real manifest is written in
/// and declines to guess at the rest, which is the trade this tool makes
/// everywhere: be certain about the common case, silent about the rest.
public enum SyntaxReader {
    /// The literal text of a string expression, or nil when the value is
    /// computed and therefore not knowable without running the manifest.
    public static func stringValue(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        var text = ""
        for segment in literal.segments {
            guard let piece = segment.as(StringSegmentSyntax.self) else { return nil }
            text += piece.content.text
        }
        return text
    }

    public static func arrayElements(_ expression: ExprSyntax) -> [ExprSyntax] {
        guard let array = expression.as(ArrayExprSyntax.self) else { return [] }
        return array.elements.map(\.expression)
    }

    public static func stringArray(_ expression: ExprSyntax) -> [String] {
        arrayElements(expression).compactMap(stringValue)
    }

    /// A call written as `.target(...)` or `Package(...)`, reduced to the name
    /// being called and its arguments.
    public static func call(_ expression: ExprSyntax) -> (name: String, arguments: LabeledExprListSyntax)? {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return (member.declName.baseName.text, call.arguments)
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return (reference.baseName.text, call.arguments)
        }
        return nil
    }

    public static func argument(_ label: String, in arguments: LabeledExprListSyntax) -> ExprSyntax? {
        arguments.first { $0.label?.text == label }?.expression
    }

    /// The name a bare `.member` reference carries, as in a dependency written
    /// `.byName(name: "X")` or a product type written `.library`.
    public static func memberName(_ expression: ExprSyntax) -> String? {
        expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }
}
