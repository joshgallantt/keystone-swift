import Foundation
import SwiftParser
import SwiftSyntax

/// Turns Swift source into facts, using a real parser.
///
/// The regex alternative was considered and rejected. `class FooRepository` is
/// easy; the same words inside a doc comment, a string literal, a `#if` branch
/// or a nested type are what separate a tool that is trusted from one that is
/// switched off. A parser is right about all four without being told, and the
/// promise this tool makes is determinism — which is worth nothing if the thing
/// being determined is wrong.
public struct SwiftSourceAnalyzer: Sendable {
    public init() {}

    public func analyze(path: String, content: String) -> SourceFacts {
        let tree = Parser.parse(source: content)
        let converter = SourceLocationConverter(fileName: path, tree: tree)
        let visitor = FactVisitor(converter: converter)
        visitor.walk(tree)

        return SourceFacts(
            path: path,
            imports: visitor.imports,
            declarations: visitor.declarations,
            extensions: visitor.extensions,
            typeReferences: visitor.orderedTypeReferences,
            comments: CommentScanner.scan(tree: tree, converter: converter),
            tests: visitor.tests
        )
    }
}

private final class FactVisitor: SyntaxVisitor {
    let converter: SourceLocationConverter
    var imports: [ImportReference] = []
    var declarations: [Declaration] = []
    var extensions: [Declaration] = []
    var tests: [TestDeclaration] = []
    private var typeReferences: [String: Int] = [:]
    private var nestingDepth = 0

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// First occurrence wins, so a report points at where a type entered the
    /// file rather than at an arbitrary later mention.
    var orderedTypeReferences: [TypeReference] {
        typeReferences
            .map { TypeReference(name: $0.key, line: $0.value) }
            .sorted { $0.line == $1.line ? $0.name < $1.name : $0.line < $1.line }
    }

    private func line(_ node: some SyntaxProtocol) -> Int {
        node.startLocation(converter: converter).line
    }

    private func note(_ name: String, at line: Int) {
        guard let existing = typeReferences[name] else {
            typeReferences[name] = line
            return
        }
        if line < existing { typeReferences[name] = line }
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // `import struct Money.Currency` names the module in the first
        // component; the rest is the symbol being narrowed to, and a narrowed
        // import crosses exactly the same boundary as a whole one.
        let components = node.path.map(\.name.text)
        guard let module = components.first else { return .skipChildren }
        let isTestable = node.attributes.contains { attribute in
            attribute.as(AttributeSyntax.self)?
                .attributeName.as(IdentifierTypeSyntax.self)?.name.text == "testable"
        }
        imports.append(ImportReference(module: module, line: line(node), isTestable: isTestable))
        return .skipChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .protocol, node: node, modifiers: node.modifiers, inheritance: node.inheritanceClause)
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .struct, node: node, modifiers: node.modifiers, inheritance: node.inheritanceClause)
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .class, node: node, modifiers: node.modifiers, inheritance: node.inheritanceClause)
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .actor, node: node, modifiers: node.modifiers, inheritance: node.inheritanceClause)
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .enum, node: node, modifiers: node.modifiers, inheritance: node.inheritanceClause)
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, kind: .typealias_, node: node, modifiers: node.modifiers, inheritance: nil)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let name = FactVisitor.declaredTypeName(node.extendedType) {
            extensions.append(
                Declaration(
                    name: name,
                    kind: .extension,
                    line: line(node),
                    accessLevel: FactVisitor.accessLevel(node.modifiers),
                    inheritedTypes: node.inheritanceClause?.inheritedTypes.compactMap {
                        FactVisitor.declaredTypeName($0.type)
                    } ?? [],
                    isTopLevel: nestingDepth == 0,
                    isConstrained: node.genericWhereClause != nil
                )
            )
        }
        nestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { nestingDepth -= 1 }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        if let attribute = node.attributes.lazy.compactMap({ $0.as(AttributeSyntax.self) }).first(where: {
            $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Test"
        }) {
            tests.append(
                TestDeclaration(
                    functionName: name,
                    displayName: FactVisitor.firstStringArgument(of: attribute),
                    line: line(node),
                    style: .swiftTesting
                )
            )
            return .visitChildren
        }

        // XCTest's convention. Checked by name because that is genuinely all
        // XCTest gives you — the runner finds tests the same way.
        if name.hasPrefix("test"), node.signature.parameterClause.parameters.isEmpty {
            tests.append(TestDeclaration(functionName: name, line: line(node), style: .xctest))
        }

        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = node.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
        guard isStatic else { return .visitChildren }
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            declarations.append(
                Declaration(
                    name: pattern.identifier.text,
                    kind: .variable,
                    line: line(node),
                    accessLevel: FactVisitor.accessLevel(node.modifiers),
                    isTopLevel: nestingDepth == 0,
                    isStatic: true
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        note(node.name.text, at: line(node))
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        if let root = FactVisitor.rootTypeName(TypeSyntax(node)) {
            note(root, at: line(node))
        }
        return .visitChildren
    }

    /// A capitalised identifier in expression position is a type being used —
    /// `URLSession.shared`, `Money(...)`, `Product.self`. The convention is
    /// not law, so this is deliberately a lower-confidence signal, and the
    /// rules that read it say so by skipping any name that more than one
    /// module declares.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if let first = name.first, first.isUppercase {
            note(name, at: line(node))
        }
        return .visitChildren
    }

    private func record(
        name: String,
        kind: DeclarationKind,
        node: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        inheritance: InheritanceClauseSyntax?
    ) {
        declarations.append(
            Declaration(
                name: name,
                kind: kind,
                line: line(node),
                accessLevel: FactVisitor.accessLevel(modifiers),
                inheritedTypes: inheritance?.inheritedTypes.compactMap { FactVisitor.declaredTypeName($0.type) } ?? [],
                isTopLevel: nestingDepth == 0
            )
        )
    }

    /// The sentence in `@Test("…")`, ignoring traits that follow it.
    static func firstStringArgument(of attribute: AttributeSyntax) -> String? {
        guard case .argumentList(let arguments) = attribute.arguments else { return nil }
        for argument in arguments where argument.label == nil {
            if let value = SyntaxReader.stringValue(argument.expression) { return value }
        }
        return nil
    }

    static func accessLevel(_ modifiers: DeclModifierListSyntax) -> AccessLevel {
        for modifier in modifiers {
            if let level = AccessLevel(rawValue: modifier.name.text) { return level }
        }
        return .internal
    }

    /// The leftmost identifier of a possibly-qualified type, so that
    /// `extension Money.Currency` is understood to reopen `Money`.
    /// The type a qualified name actually denotes: the rightmost component.
    ///
    /// `rootTypeName` answers the opposite question — what a reference *mentions*
    /// first — and for `SwiftUI.View` that is `SwiftUI`, which is a module. Used
    /// for a declaration it produced `extension SwiftUI`, so a file extending
    /// `SwiftUI.View` was reported as reopening a type called `SwiftUI`, and
    /// `extension Mastodon.Status` as reopening `Mastodon`. Twenty-one of
    /// `extension-boundary`'s twenty-one findings across thirty-two apps were
    /// that mistake and nothing else.
    static func declaredTypeName(_ type: TypeSyntax) -> String? {
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        if let optional = type.as(OptionalTypeSyntax.self) { return declaredTypeName(optional.wrappedType) }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return declaredTypeName(implicit.wrappedType) }
        if let attributed = type.as(AttributedTypeSyntax.self) { return declaredTypeName(attributed.baseType) }
        if let some = type.as(SomeOrAnyTypeSyntax.self) { return declaredTypeName(some.constraint) }
        return rootTypeName(type)
    }

    static func rootTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
        if let member = type.as(MemberTypeSyntax.self) { return rootTypeName(member.baseType) }
        if let optional = type.as(OptionalTypeSyntax.self) { return rootTypeName(optional.wrappedType) }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return rootTypeName(implicit.wrappedType) }
        if let attributed = type.as(AttributedTypeSyntax.self) { return rootTypeName(attributed.baseType) }
        if let array = type.as(ArrayTypeSyntax.self) { return rootTypeName(array.element) }
        if let some = type.as(SomeOrAnyTypeSyntax.self) { return rootTypeName(some.constraint) }
        return nil
    }
}

/// Comments, read from trivia rather than from the raw text, so that a `TODO`
/// inside a string literal is not mistaken for one in a comment.
private enum CommentScanner {
    static func scan(tree: SourceFileSyntax, converter: SourceLocationConverter) -> [CommentMatch] {
        var matches: [CommentMatch] = []

        for token in tree.tokens(viewMode: .sourceAccurate) {
            collect(token.leadingTrivia, from: token.position, into: &matches, converter: converter)
            collect(token.trailingTrivia, from: token.endPositionBeforeTrailingTrivia, into: &matches, converter: converter)
        }

        return matches.sorted { $0.line == $1.line ? $0.text < $1.text : $0.line < $1.line }
    }

    private static func collect(
        _ trivia: Trivia,
        from start: AbsolutePosition,
        into matches: inout [CommentMatch],
        converter: SourceLocationConverter
    ) {
        var position = start
        for piece in trivia {
            defer { position += piece.sourceLength }
            let text: String
            switch piece {
            case .lineComment(let value), .blockComment(let value),
                 .docLineComment(let value), .docBlockComment(let value):
                text = value
            default:
                continue
            }
            matches.append(CommentMatch(text: text, line: converter.location(for: position).line))
        }
    }
}
