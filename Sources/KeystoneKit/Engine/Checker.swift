import Foundation

public struct CheckResult: Sendable {
    public var violations: [Violation]
    public var filesChecked: Int
    public var assignment: RoleAssignment
    public var graph: ProjectGraph
    public var scannedFiles: [String]
    /// Every file that was parsed, with its role and its facts. `freeze` reads
    /// the imports from here: a manifest edge and an `import` are different
    /// evidence, and `dependency-rule` fires on the second.
    public var files: [AnalyzedFile] = []

    public var errors: [Violation] { violations.errors }
    public var warnings: [Violation] { violations.warnings }
    public var hasErrors: Bool { !errors.isEmpty }
}

/// A file about to be written, which does not exist on disk in this form yet.
public struct PendingFile: Sendable {
    public var path: String
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

/// Runs the rules.
///
/// There are two entry points because there are two questions. `checkProject`
/// answers "is this codebase sound", and can take as long as it needs.
/// `checkPending` answers "may this write land", is called before every edit an
/// agent makes, and therefore parses exactly one file — the graph and the layer
/// assignment come from paths and manifests, which are cheap to read and do not
/// need the rest of the source at all.
public struct Checker: Sendable {
    private let fileSystem: FileSystemProbing
    private let analyzer = SwiftSourceAnalyzer()

    public init(fileSystem: FileSystemProbing = RealFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func checkProject(
        root: String,
        configuration: Configuration,
        limitedTo paths: Set<String>? = nil
    ) -> CheckResult {
        let root = Paths.canonical(root)
        let scanner = ProjectScanner(fileSystem: fileSystem)
        let scanned = scanner.scan(root: root, configuration: configuration)
        // Parse before placing. A file's contents are evidence about its layer,
        // so the facts have to exist before the layers are decided.
        var parsed: [String: SourceFacts] = [:]
        parsed.reserveCapacity(scanned.swiftFiles.count)
        for path in scanned.swiftFiles {
            guard let content = fileSystem.contents(of: Paths.absolute(path, in: root)) else { continue }
            parsed[path] = analyzer.analyze(path: path, content: content)
        }

        let assignment = RoleAssignment(
            configuration: configuration,
            graph: scanned.graph,
            swiftFiles: scanned.swiftFiles,
            facts: parsed
        )

        var files: [AnalyzedFile] = []
        files.reserveCapacity(parsed.count)
        for path in scanned.swiftFiles {
            guard let facts = parsed[path] else { continue }
            files.append(
                AnalyzedFile(
                    path: path,
                    role: assignment.role(ofFile: path),
                    module: scanned.graph.module(owning: path),
                    facts: facts
                )
            )
        }

        let context = RuleContext(
            configuration: configuration,
            graph: scanned.graph,
            assignment: assignment,
            symbols: SymbolIndex.build(files: files, graph: scanned.graph),
            catalog: configuration.catalog,
            files: files,
            allFiles: scanned.allFiles,
            scope: .project
        )

        var violations = run(RuleRegistry.all, in: context, configuration: configuration)
        if let paths {
            violations = violations.filter { paths.contains($0.file) }
        }

        return CheckResult(
            violations: violations,
            filesChecked: files.count,
            assignment: assignment,
            graph: scanned.graph,
            scannedFiles: scanned.swiftFiles,
            files: files
        )
    }

    /// One file, judged against the rules that can decide from one file.
    ///
    /// Rules needing the whole project are skipped rather than approximated.
    /// A cycle check run against a single file would report no cycles, which
    /// is worse than reporting nothing: it reads as a pass.
    public func checkPending(
        root: String,
        configuration: Configuration,
        pending: PendingFile
    ) -> CheckResult {
        let root = Paths.canonical(root)
        let scanner = ProjectScanner(fileSystem: fileSystem)
        let scanned = scanner.scan(root: root, configuration: configuration)

        // The pending file may be new, so make sure the layer assignment knows
        // about it even though the walk did not find it.
        var known = scanned.swiftFiles
        if !known.contains(pending.path) {
            known.append(pending.path)
            known.sort()
        }

        let pendingFacts = analyzer.analyze(path: pending.path, content: pending.content)
        let assignment = RoleAssignment(
            configuration: configuration,
            graph: scanned.graph,
            swiftFiles: known,
            facts: [pending.path: pendingFacts]
        )

        let file = AnalyzedFile(
            path: pending.path,
            role: assignment.role(ofFile: pending.path),
            module: scanned.graph.module(owning: pending.path),
            facts: pendingFacts
        )

        let context = RuleContext(
            configuration: configuration,
            graph: scanned.graph,
            assignment: assignment,
            symbols: SymbolIndex(entries: []),
            catalog: configuration.catalog,
            files: [file],
            scope: .singleFile
        )

        return CheckResult(
            violations: run(RuleRegistry.perFile, in: context, configuration: configuration),
            filesChecked: 1,
            assignment: assignment,
            graph: scanned.graph,
            scannedFiles: known,
            files: [file]
        )
    }

    /// Applies the project's own severity choices last, so a rule's default is
    /// a starting position rather than a verdict.
    private func run(_ rules: [any Rule], in context: RuleContext, configuration: Configuration) -> [Violation] {
        var violations: [Violation] = []

        for rule in rules {
            guard rule.emittedIdentifiers.contains(where: configuration.isEnabled) else { continue }
            for violation in rule.evaluate(context) {
                guard configuration.isEnabled(violation.rule) else { continue }
                var adjusted = violation
                adjusted.severity = configuration.severity(for: violation.rule, default: violation.severity)
                violations.append(adjusted)
            }
        }

        return violations.sortedForReport()
    }
}
