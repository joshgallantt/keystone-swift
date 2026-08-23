import Foundation
import Testing
@testable import KeystoneKit

@Suite("Xcode projects")
struct XcodeProjectParserTests {
    /// A pbxproj states a file's location as one path component plus a promise
    /// about where to start, so nothing means anything until the group tree is
    /// walked upward. Both of Xcode's ways of claiming files are covered here:
    /// the hand-maintained build-file list, and the synchronised folder that
    /// replaced it in Xcode 16.
    let project = """
    // !$*UTF8*$!
    {
        objects = {
            ROOTGROUP = {
                isa = PBXGroup;
                children = (APPGROUP, SYNCGROUP);
                sourceTree = "<group>";
            };
            APPGROUP = {
                isa = PBXGroup;
                children = (MODELGROUP);
                path = App;
                sourceTree = "<group>";
            };
            MODELGROUP = {
                isa = PBXGroup;
                children = (ORDERFILE);
                path = Domain;
                sourceTree = "<group>";
            };
            ORDERFILE = {
                isa = PBXFileReference;
                path = Order.swift;
                sourceTree = "<group>";
            };
            SYNCGROUP = {
                isa = PBXFileSystemSynchronizedRootGroup;
                path = Features;
                sourceTree = "<group>";
            };
            BUILDFILE = { isa = PBXBuildFile; fileRef = ORDERFILE; };
            SOURCES = { isa = PBXSourcesBuildPhase; files = (BUILDFILE); };
            REMOTEPKG = {
                isa = XCRemoteSwiftPackageReference;
                repositoryURL = "https://github.com/example/Kingfisher.git";
            };
            KINGFISHER = { isa = XCSwiftPackageProductDependency; productName = Kingfisher; };
            APPTARGET = {
                isa = PBXNativeTarget;
                name = MyApp;
                productType = "com.apple.product-type.application";
                buildPhases = (SOURCES);
                fileSystemSynchronizedGroups = (SYNCGROUP);
                packageProductDependencies = (KINGFISHER);
                dependencies = ();
            };
            TESTTARGET = {
                isa = PBXNativeTarget;
                name = MyAppTests;
                productType = "com.apple.product-type.bundle.unit-test";
                buildPhases = ();
                dependencies = ();
            };
        };
    }
    """

    @Test("a file's path is recovered by walking the group tree upward")
    func resolvesPathsThroughGroups() {
        let parsed = XcodeProjectParser().parse(source: project, projectPath: "MyApp.xcodeproj")
        let app = parsed?.targets.first { $0.name == "MyApp" }

        #expect(app?.explicitFiles == ["App/Domain/Order.swift"])
    }

    @Test("an Xcode 16 synchronised folder is claimed as a directory, not a file list")
    func readsSynchronisedFolders() {
        let parsed = XcodeProjectParser().parse(source: project, projectPath: "MyApp.xcodeproj")
        let app = parsed?.targets.first { $0.name == "MyApp" }

        #expect(app?.sourceRoots == ["Features"])
    }

    @Test("product type decides the kind, and remote packages are recorded as external")
    func readsKindsAndPackages() {
        let parsed = XcodeProjectParser().parse(source: project, projectPath: "MyApp.xcodeproj")

        #expect(parsed?.targets.first { $0.name == "MyApp" }?.kind == .app)
        #expect(parsed?.targets.first { $0.name == "MyAppTests" }?.kind == .test)
        #expect(parsed?.externalPackages == ["Kingfisher"])
        #expect(parsed?.targets.first { $0.name == "MyApp" }?.declaredDependencies == ["Kingfisher"])
    }

    @Test("a project nested in the repository resolves against its own directory")
    func resolvesRelativeToTheProjectDirectory() {
        let parsed = XcodeProjectParser().parse(source: project, projectPath: "Apps/MyApp.xcodeproj")
        let app = parsed?.targets.first { $0.name == "MyApp" }

        #expect(app?.explicitFiles == ["Apps/App/Domain/Order.swift"])
        #expect(app?.sourceRoots == ["Apps/Features"])
    }
}
