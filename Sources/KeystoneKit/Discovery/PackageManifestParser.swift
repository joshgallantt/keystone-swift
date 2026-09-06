import Foundation
import SwiftParser
import SwiftSyntax

public struct ParsedPackage: Sendable {
    public var name: String
    /// Repository-relative directory containing `Package.swift`.
    public var directory: String
    public var manifestPath: String
    public var products: [ProductInfo]
    public var targets: [Module]
    /// Identities of packages fetched from a URL — anything not ours.
    public var externalPackages: Set<String>
    /// Repository-relative directories of sibling packages depended on by path.
    public var localPackages: [String]
}

/// Reads `Package.swift` as text.
///
/// The manifest is the only place an SPM boundary is real: two targets cannot
/// see each other unless this file says so, whatever their imports claim. That
/// makes it worth parsing exactly, and worth failing quietly on — a manifest
/// that computes its target list is a manifest this tool declines to have an
/// opinion about, rather than one it guesses at.
public struct PackageManifestParser: Sendable {
    private let fileSystem: FileSystemProbing

    public init(fileSystem: FileSystemProbing = RealFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func parse(source: String, manifestPath: String, root: String) -> ParsedPackage? {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: manifestPath, tree: tree)
        guard let packageCall = PackageCallFinder.find(in: tree) else { return nil }

        let directory = Paths.directory(of: manifestPath)
        let arguments = packageCall.arguments

        guard let nameExpression = SyntaxReader.argument("name", in: arguments),
              let name = SyntaxReader.stringValue(nameExpression) else { return nil }

        var external: Set<String> = []
        var local: [String] = []
        if let dependencies = SyntaxReader.argument("dependencies", in: arguments) {
            for element in SyntaxReader.arrayElements(dependencies) {
                guard let call = SyntaxReader.call(element), call.name == "package" else { continue }
                if let url = SyntaxReader.argument("url", in: call.arguments),
                   let value = SyntaxReader.stringValue(url) {
                    external.insert(PackageManifestParser.identity(fromURL: value))
                } else if let path = SyntaxReader.argument("path", in: call.arguments),
                          let value = SyntaxReader.stringValue(path) {
                    local.append(Paths.normalise(Paths.join(directory, value)))
                }
            }
        }

        // Read from the whole file, not from a literal array under `products:`
        // and `targets:`. A manifest is a Swift program and real ones use it —
        // `targets: XcodeSupport.targets + [...]` in WordPress, a helper in
        // others, a `#if` in some. The declarations are still literally present;
        // only their position in the syntax tree differs.
        var products: [ProductInfo] = []
        for call in SyntaxReader.calls(named: ["library", "executable"], under: tree) {
            guard let nameExpression = SyntaxReader.argument("name", in: call.arguments),
                  let productName = SyntaxReader.stringValue(nameExpression) else { continue }
            let targets = SyntaxReader.argument("targets", in: call.arguments)
                .map(SyntaxReader.stringArray) ?? []
            products.append(ProductInfo(name: productName, targets: targets, packageName: name))
        }

        var targets: [Module] = []
        var seen: Set<String> = []
        for call in SyntaxReader.calls(
            named: ["target", "macro", "executableTarget", "testTarget", "systemLibrary", "binaryTarget", "plugin"],
            under: tree
        ) {
            guard let callee = SyntaxReader.memberName(ExprSyntax(call.calledExpression)),
                  let kind = PackageManifestParser.kind(forCall: callee) else { continue }
            let line = call.startLocation(converter: converter).line
            if let module = target(
                from: call.arguments,
                kind: kind,
                packageName: name,
                directory: directory,
                manifestPath: manifestPath,
                line: line,
                root: root
            ), seen.insert(module.name).inserted {
                targets.append(module)
            }
        }

        return ParsedPackage(
            name: name,
            directory: directory,
            manifestPath: manifestPath,
            products: products,
            targets: targets,
            externalPackages: external,
            localPackages: local
        )
    }

    private func target(
        from arguments: LabeledExprListSyntax,
        kind: ModuleKind,
        packageName: String,
        directory: String,
        manifestPath: String,
        line: Int,
        root: String
    ) -> Module? {
        guard let nameExpression = SyntaxReader.argument("name", in: arguments),
              let name = SyntaxReader.stringValue(nameExpression) else { return nil }

        let declared = SyntaxReader.argument("dependencies", in: arguments)
            .map { SyntaxReader.arrayElements($0).compactMap(PackageManifestParser.dependencyName) } ?? []

        let explicitPath = SyntaxReader.argument("path", in: arguments).flatMap(SyntaxReader.stringValue)
        let base = explicitPath.map { Paths.normalise(Paths.join(directory, $0)) }
            ?? defaultBase(for: name, kind: kind, directory: directory, root: root)

        let sources = SyntaxReader.argument("sources", in: arguments).map(SyntaxReader.stringArray) ?? []
        let excludes = SyntaxReader.argument("exclude", in: arguments).map(SyntaxReader.stringArray) ?? []

        // `sources:` replaces the target's roots outright; `exclude:` trims what
        // is left. Getting this pair right is what lets three targets share one
        // `Sources/` directory, which is how a component keeps its domain, its
        // data and its wiring in one package without merging them into one
        // module.
        let roots = sources.isEmpty
            ? [base]
            : sources.map { Paths.normalise(Paths.join(base, $0)) }

        return Module(
            name: name,
            kind: kind,
            packageName: packageName,
            packageDirectory: directory,
            sourceRoots: roots,
            excludedPaths: excludes.map { Paths.normalise(Paths.join(base, $0)) },
            declaredDependencies: declared,
            manifestPath: manifestPath,
            manifestLine: line
        )
    }

    /// SwiftPM's layout conventions, checked against the disk rather than
    /// assumed, so an older package laid out as `Source/` or `src/` is read
    /// correctly instead of being reported as having no files.
    private func defaultBase(for name: String, kind: ModuleKind, directory: String, root: String) -> String {
        let candidates = kind.isTest
            ? ["Tests/\(name)"]
            : ["Sources/\(name)", "Source/\(name)", "src/\(name)", "Sources", "Source"]
        for candidate in candidates {
            let relative = Paths.normalise(Paths.join(directory, candidate))
            if fileSystem.directoryExists(at: Paths.absolute(relative, in: root)) { return relative }
        }
        return Paths.normalise(Paths.join(directory, candidates[0]))
    }

    static func kind(forCall name: String) -> ModuleKind? {
        switch name {
        case "target", "macro": return .library
        case "executableTarget": return .executable
        case "testTarget": return .test
        case "systemLibrary": return .system
        case "binaryTarget": return .binary
        case "plugin": return .plugin
        default: return nil
        }
    }

    /// A target dependency written any of the four ways SwiftPM accepts.
    static func dependencyName(_ expression: ExprSyntax) -> String? {
        if let literal = SyntaxReader.stringValue(expression) { return literal }
        guard let call = SyntaxReader.call(expression) else { return nil }
        switch call.name {
        case "product", "target", "byName":
            return SyntaxReader.argument("name", in: call.arguments).flatMap(SyntaxReader.stringValue)
        default:
            return nil
        }
    }

    static func identity(fromURL url: String) -> String {
        var last = Paths.lastComponent(of: url)
        if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
        return last
    }
}

/// Finds the `Package(...)` call without walking into anything else, since a
/// manifest may define helpers above it that also look like calls.
private enum PackageCallFinder {
    static func find(in tree: SourceFileSyntax) -> FunctionCallExprSyntax? {
        let visitor = Visitor(viewMode: .sourceAccurate)
        visitor.walk(tree)
        return visitor.found
    }

    private final class Visitor: SyntaxVisitor {
        var found: FunctionCallExprSyntax?

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            guard found == nil else { return .skipChildren }
            if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
               reference.baseName.text == "Package" {
                found = node
                return .skipChildren
            }
            return .visitChildren
        }
    }
}
