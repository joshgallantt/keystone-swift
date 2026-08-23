import Foundation

public struct ParsedXcodeProject: Sendable {
    public var name: String
    /// Repository-relative directory containing the `.xcodeproj`, which is
    /// what `SOURCE_ROOT` resolves to.
    public var directory: String
    public var manifestPath: String
    public var targets: [Module]
    public var externalPackages: Set<String>
    public var localPackages: [String]
}

/// Reads target membership out of `project.pbxproj`.
///
/// Most iOS apps are still one Xcode project, so a tool that only understood
/// SwiftPM would enforce nothing on the majority of the codebases it claims to
/// serve. Xcode has two ways of saying which files a target compiles — a
/// hand-maintained list of build files, and, since Xcode 16, a folder the
/// target simply synchronises with — and both are read here.
public struct XcodeProjectParser: Sendable {
    public init() {}

    public func parse(source: String, projectPath: String) -> ParsedXcodeProject? {
        guard let root = OpenStepPlist.parse(source),
              let objects = root["objects"]?.dictionaryValue else { return nil }

        // `projectPath` points at the bundle; SOURCE_ROOT is its parent.
        let projectDirectory = Paths.directory(of: projectPath)
        let manifestPath = Paths.join(projectPath, "project.pbxproj")
        let name = Paths.lastComponent(of: projectPath)
            .replacingOccurrences(of: ".xcodeproj", with: "")

        let resolver = PathResolver(objects: objects, projectDirectory: projectDirectory)

        var targets: [Module] = []
        var external: Set<String> = []
        var local: [String] = []

        for (identifier, object) in objects {
            guard let isa = object["isa"]?.stringValue else { continue }
            switch isa {
            case "XCRemoteSwiftPackageReference":
                if let url = object["repositoryURL"]?.stringValue {
                    external.insert(PackageManifestParser.identity(fromURL: url))
                }
            case "XCLocalSwiftPackageReference":
                if let relative = object["relativePath"]?.stringValue {
                    local.append(Paths.normalise(Paths.join(projectDirectory, relative)))
                }
            case "PBXNativeTarget":
                if let module = target(
                    identifier: identifier,
                    object: object,
                    objects: objects,
                    resolver: resolver,
                    projectName: name,
                    projectDirectory: projectDirectory,
                    manifestPath: manifestPath
                ) {
                    targets.append(module)
                }
            default:
                continue
            }
        }

        // Object order in a pbxproj is not meaningful and not stable, so the
        // result is ordered here rather than left to the dictionary.
        targets.sort { $0.name < $1.name }
        local.sort()

        return ParsedXcodeProject(
            name: name,
            directory: projectDirectory,
            manifestPath: manifestPath,
            targets: targets,
            externalPackages: external,
            localPackages: local
        )
    }

    private func target(
        identifier: String,
        object: PlistValue,
        objects: [String: PlistValue],
        resolver: PathResolver,
        projectName: String,
        projectDirectory: String,
        manifestPath: String
    ) -> Module? {
        guard let name = object["name"]?.stringValue else { return nil }
        let kind = XcodeProjectParser.kind(forProductType: object["productType"]?.stringValue)

        var files: Set<String> = []
        for phaseIdentifier in object["buildPhases"]?.stringArray ?? [] {
            guard let phase = objects[phaseIdentifier],
                  phase["isa"]?.stringValue == "PBXSourcesBuildPhase" else { continue }
            for buildFileIdentifier in phase["files"]?.stringArray ?? [] {
                guard let buildFile = objects[buildFileIdentifier],
                      let reference = buildFile["fileRef"]?.stringValue,
                      let path = resolver.path(of: reference),
                      path.hasSuffix(".swift") else { continue }
                files.insert(path)
            }
        }

        // Xcode 16's synchronised folders: the target compiles whatever is in
        // the directory, so the directory is the claim and no file list exists.
        var roots: [String] = []
        for groupIdentifier in object["fileSystemSynchronizedGroups"]?.stringArray ?? [] {
            if let path = resolver.path(of: groupIdentifier) { roots.append(path) }
        }

        var dependencies: [String] = []
        for dependencyIdentifier in object["dependencies"]?.stringArray ?? [] {
            guard let dependency = objects[dependencyIdentifier] else { continue }
            if let targetIdentifier = dependency["target"]?.stringValue,
               let dependencyName = objects[targetIdentifier]?["name"]?.stringValue {
                dependencies.append(dependencyName)
            } else if let literal = dependency["name"]?.stringValue {
                dependencies.append(literal)
            } else if let productIdentifier = dependency["productRef"]?.stringValue,
                      let product = objects[productIdentifier]?["productName"]?.stringValue {
                dependencies.append(product)
            }
        }
        for productIdentifier in object["packageProductDependencies"]?.stringArray ?? [] {
            if let product = objects[productIdentifier]?["productName"]?.stringValue {
                dependencies.append(product)
            }
        }

        return Module(
            name: name,
            kind: kind,
            packageName: projectName,
            packageDirectory: projectDirectory,
            sourceRoots: roots.sorted(),
            declaredDependencies: dependencies.sorted(),
            explicitFiles: files,
            manifestPath: manifestPath
        )
    }

    static func kind(forProductType productType: String?) -> ModuleKind {
        guard let productType else { return .library }
        if productType.contains("bundle.unit-test") || productType.contains("bundle.ui-testing") {
            return .test
        }
        if productType.contains("product-type.application") || productType.contains("extension") {
            return .app
        }
        if productType.contains("product-type.tool") { return .executable }
        return .library
    }
}

/// Turns an object identifier into a repository-relative path by walking the
/// group tree upward, which is the only way a pbxproj path means anything: a
/// file reference stores one path component and a promise about where to start.
private struct PathResolver {
    let objects: [String: PlistValue]
    let projectDirectory: String
    private let parents: [String: String]

    init(objects: [String: PlistValue], projectDirectory: String) {
        self.objects = objects
        self.projectDirectory = projectDirectory

        var parents: [String: String] = [:]
        for (identifier, object) in objects {
            for child in object["children"]?.stringArray ?? [] {
                parents[child] = identifier
            }
        }
        self.parents = parents
    }

    func path(of identifier: String) -> String? {
        resolve(identifier, depth: 0)
    }

    private func resolve(_ identifier: String, depth: Int) -> String? {
        // A malformed project could describe a cycle. Bounding the walk keeps
        // a bad file from hanging a hook that has to answer in milliseconds.
        guard depth < 64, let object = objects[identifier] else { return nil }

        let ownPath = object["path"]?.stringValue ?? ""
        let sourceTree = object["sourceTree"]?.stringValue ?? "<group>"

        switch sourceTree {
        case "<absolute>":
            return ownPath.isEmpty ? nil : ownPath
        case "SOURCE_ROOT", "":
            return Paths.normalise(Paths.join(projectDirectory, ownPath))
        case "SDKROOT", "BUILT_PRODUCTS_DIR", "DEVELOPER_DIR", "PLATFORM_DIR":
            // Somebody else's file. Not ours to have an opinion about.
            return nil
        default:
            guard let parent = parents[identifier] else {
                return Paths.normalise(Paths.join(projectDirectory, ownPath))
            }
            guard let base = resolve(parent, depth: depth + 1) else { return nil }
            return Paths.normalise(Paths.join(base, ownPath))
        }
    }
}
